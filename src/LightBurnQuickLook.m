#import <Foundation/Foundation.h>
#import <CoreFoundation/CFPlugInCOM.h>
#import <QuickLook/QuickLook.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#import <libxml/xmlreader.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define PLUGIN_ID "b7150805-8a7a-4e1b-aef3-56a1a68c1eab"

static const unsigned long long kMaximumProjectBytes = 256ULL * 1024ULL * 1024ULL;
static const unsigned long long kMaximumPNGBytes = 32ULL * 1024ULL * 1024ULL;
static const unsigned long long kMaximumBase64Bytes = ((kMaximumPNGBytes + 2ULL) / 3ULL) * 4ULL + 4ULL;
static const unsigned long long kMaximumImagePixels = 16ULL * 1024ULL * 1024ULL;
static const unsigned long long kMaximumImageDimension = 8192ULL;

typedef struct __LightBurnQuickLookPlugin {
    void *conduitInterface;
    CFUUIDRef factoryID;
    volatile UInt32 refCount;
} LightBurnQuickLookPlugin;

static OSStatus GenerateThumbnailForURL(void *thisInterface,
                                         QLThumbnailRequestRef thumbnail,
                                         CFURLRef url,
                                         CFStringRef contentTypeUTI,
                                         CFDictionaryRef options,
                                         CGSize maxSize);
static void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail);
static OSStatus GeneratePreviewForURL(void *thisInterface,
                                      QLPreviewRequestRef preview,
                                      CFURLRef url,
                                      CFStringRef contentTypeUTI,
                                      CFDictionaryRef options);
static void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview);

static HRESULT QuickLookGeneratorQueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv);
static ULONG QuickLookGeneratorPluginAddRef(void *thisInstance);
static ULONG QuickLookGeneratorPluginRelease(void *thisInstance);
static LightBurnQuickLookPlugin *AllocatePlugin(CFUUIDRef factoryID);
static void DeallocatePlugin(LightBurnQuickLookPlugin *plugin);

static QLGeneratorInterfaceStruct gInterfaceTable = {
    NULL,
    QuickLookGeneratorQueryInterface,
    QuickLookGeneratorPluginAddRef,
    QuickLookGeneratorPluginRelease,
    NULL,
    NULL,
    NULL,
    NULL
};

static void IgnoreXMLReaderError(void *context,
                                 const char *message,
                                 xmlParserSeverities severity,
                                 xmlTextReaderLocatorPtr locator) {
    (void)context;
    (void)message;
    (void)severity;
    (void)locator;
}

static NSData *ReadProjectData(CFURLRef url) {
    if (url == NULL) return nil;

    NSURL *fileURL = (__bridge NSURL *)url;
    if (!fileURL.isFileURL) return nil;
    NSString *path = [fileURL path];
    if (path.length == 0) return nil;

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    NSNumber *fileSize = attributes[NSFileSize];
    if (fileSize == nil || fileSize.unsignedLongLongValue > kMaximumProjectBytes) return nil;

    NSData *data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:NULL];
    if (data.length == 0 || data.length > kMaximumProjectBytes) return nil;
    return data;
}

static NSData *DecodePNGAttribute(xmlChar *attributeValue) {
    if (attributeValue == NULL) return nil;

    size_t sourceLength = strlen((const char *)attributeValue);
    if (sourceLength == 0 || sourceLength > kMaximumBase64Bytes) return nil;

    char *compactBase64 = malloc(sourceLength + 1);
    if (compactBase64 == NULL) return nil;

    size_t outputLength = 0;
    BOOL valid = YES;
    for (size_t index = 0; index < sourceLength; index++) {
        unsigned char character = attributeValue[index];
        if (character == ' ' || character == '\t' || character == '\r' || character == '\n') continue;

        BOOL isBase64 = (character >= 'A' && character <= 'Z') ||
                        (character >= 'a' && character <= 'z') ||
                        (character >= '0' && character <= '9') ||
                        character == '+' || character == '/' || character == '=';
        if (!isBase64) {
            valid = NO;
            break;
        }
        compactBase64[outputLength++] = (char)character;
    }
    compactBase64[outputLength] = '\0';

    NSData *png = nil;
    if (valid && outputLength > 0) {
        NSString *base64 = [[NSString alloc] initWithBytes:compactBase64
                                                    length:outputLength
                                                  encoding:NSASCIIStringEncoding];
        if (base64 != nil) {
            png = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
        }
    }
    free(compactBase64);

    if (png.length < 24 || png.length > kMaximumPNGBytes) return nil;

    static const unsigned char pngSignature[8] = {0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
    if (memcmp(png.bytes, pngSignature, sizeof(pngSignature)) != 0) return nil;
    return png;
}

static NSData *ExtractEmbeddedPNG(CFURLRef url) {
    NSData *projectData = ReadProjectData(url);
    if (projectData == nil || projectData.length > INT32_MAX) return nil;

    xmlTextReaderPtr reader = xmlReaderForMemory((const char *)projectData.bytes,
                                                  (int)projectData.length,
                                                  "LightBurnProject.lbrn2",
                                                  NULL,
                                                  XML_PARSE_NONET | XML_PARSE_COMPACT |
                                                  XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
    if (reader == NULL) return nil;
    xmlTextReaderSetErrorHandler(reader, IgnoreXMLReaderError, NULL);

    BOOL validRoot = NO;
    BOOL sawRoot = NO;
    BOOL rejectedDocumentType = NO;
    xmlChar *encodedThumbnail = NULL;
    int readResult = 0;

    while ((readResult = xmlTextReaderRead(reader)) == 1) {
        int nodeType = xmlTextReaderNodeType(reader);
        if (nodeType == XML_READER_TYPE_DOCUMENT_TYPE) {
            rejectedDocumentType = YES;
            break;
        }
        if (nodeType != XML_READER_TYPE_ELEMENT) continue;

        int depth = xmlTextReaderDepth(reader);
        const xmlChar *name = xmlTextReaderConstLocalName(reader);
        if (depth == 0) {
            sawRoot = YES;
            validRoot = name != NULL && xmlStrEqual(name, BAD_CAST "LightBurnProject");
            if (!validRoot) break;
        } else if (depth == 1 && validRoot && name != NULL && xmlStrEqual(name, BAD_CAST "Thumbnail")) {
            encodedThumbnail = xmlTextReaderGetAttribute(reader, BAD_CAST "Source");
            if (encodedThumbnail == NULL) break;
        }
    }

    xmlFreeTextReader(reader);

    NSData *png = nil;
    if (!rejectedDocumentType && sawRoot && validRoot && encodedThumbnail != NULL) {
        png = DecodePNGAttribute(encodedThumbnail);
    }
    if (encodedThumbnail != NULL) xmlFree(encodedThumbnail);

    if (readResult < 0 || rejectedDocumentType) return nil;
    return png;
}

static BOOL IsValidPNGImage(NSData *png) {
    if (png == nil || png.length > kMaximumPNGBytes) return NO;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)png, NULL);
    if (source == NULL) return NO;

    BOOL valid = NO;
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    if (properties != NULL) {
        CFNumberRef widthValue = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
        CFNumberRef heightValue = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
        long long width = 0;
        long long height = 0;
        if (widthValue != NULL && heightValue != NULL &&
            CFNumberGetValue(widthValue, kCFNumberLongLongType, &width) &&
            CFNumberGetValue(heightValue, kCFNumberLongLongType, &height) &&
            width > 0 && height > 0 &&
            (unsigned long long)width <= kMaximumImageDimension &&
            (unsigned long long)height <= kMaximumImageDimension &&
            (unsigned long long)width <= kMaximumImagePixels / (unsigned long long)height) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
            valid = image != NULL;
            if (image != NULL) CGImageRelease(image);
        }
        CFRelease(properties);
    }
    CFRelease(source);
    return valid;
}

static NSData *ReadValidatedEmbeddedPNG(CFURLRef url) {
    NSData *png = ExtractEmbeddedPNG(url);
    return IsValidPNGImage(png) ? png : nil;
}

static OSStatus GenerateThumbnailForURL(void *thisInterface,
                                         QLThumbnailRequestRef thumbnail,
                                         CFURLRef url,
                                         CFStringRef contentTypeUTI,
                                         CFDictionaryRef options,
                                         CGSize maxSize) {
    (void)thisInterface;
    (void)contentTypeUTI;
    (void)options;
    (void)maxSize;

    if (thumbnail == NULL || QLThumbnailRequestIsCancelled(thumbnail)) return noErr;
    @autoreleasepool {
        NSData *png = ReadValidatedEmbeddedPNG(url);
        if (png == nil || QLThumbnailRequestIsCancelled(thumbnail)) return paramErr;
        QLThumbnailRequestSetImageWithData(thumbnail, (__bridge CFDataRef)png, NULL);
    }
    return noErr;
}

static void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail) {
    (void)thisInterface;
    (void)thumbnail;
}

static OSStatus GeneratePreviewForURL(void *thisInterface,
                                      QLPreviewRequestRef preview,
                                      CFURLRef url,
                                      CFStringRef contentTypeUTI,
                                      CFDictionaryRef options) {
    (void)thisInterface;
    (void)contentTypeUTI;
    (void)options;

    if (preview == NULL || QLPreviewRequestIsCancelled(preview)) return noErr;
    @autoreleasepool {
        NSData *png = ReadValidatedEmbeddedPNG(url);
        if (png == nil || QLPreviewRequestIsCancelled(preview)) return paramErr;
        QLPreviewRequestSetDataRepresentation(preview, (__bridge CFDataRef)png, kUTTypePNG, NULL);
    }
    return noErr;
}

static void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview) {
    (void)thisInterface;
    (void)preview;
}

static HRESULT QuickLookGeneratorQueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv) {
    if (ppv == NULL || thisInstance == NULL) return E_POINTER;
    *ppv = NULL;

    CFUUIDRef interfaceID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    if (interfaceID == NULL) return E_NOINTERFACE;

    BOOL supported = CFEqual(interfaceID, kQLGeneratorCallbacksInterfaceID) ||
                     CFEqual(interfaceID, IUnknownUUID);
    CFRelease(interfaceID);
    if (!supported) return E_NOINTERFACE;

    LightBurnQuickLookPlugin *plugin = (LightBurnQuickLookPlugin *)thisInstance;
    QLGeneratorInterfaceStruct *table = (QLGeneratorInterfaceStruct *)plugin->conduitInterface;
    table->GenerateThumbnailForURL = GenerateThumbnailForURL;
    table->CancelThumbnailGeneration = CancelThumbnailGeneration;
    table->GeneratePreviewForURL = GeneratePreviewForURL;
    table->CancelPreviewGeneration = CancelPreviewGeneration;
    table->AddRef(thisInstance);
    *ppv = thisInstance;
    return S_OK;
}

static ULONG QuickLookGeneratorPluginAddRef(void *thisInstance) {
    LightBurnQuickLookPlugin *plugin = (LightBurnQuickLookPlugin *)thisInstance;
    return __sync_add_and_fetch(&plugin->refCount, 1);
}

static void DeallocatePlugin(LightBurnQuickLookPlugin *plugin) {
    CFUUIDRef factoryID = plugin->factoryID;
    free(plugin->conduitInterface);
    free(plugin);
    if (factoryID != NULL) {
        CFPlugInRemoveInstanceForFactory(factoryID);
        CFRelease(factoryID);
    }
}

static ULONG QuickLookGeneratorPluginRelease(void *thisInstance) {
    LightBurnQuickLookPlugin *plugin = (LightBurnQuickLookPlugin *)thisInstance;
    UInt32 referenceCount = __sync_sub_and_fetch(&plugin->refCount, 1);
    if (referenceCount == 0) DeallocatePlugin(plugin);
    return referenceCount;
}

static LightBurnQuickLookPlugin *AllocatePlugin(CFUUIDRef factoryID) {
    LightBurnQuickLookPlugin *plugin = calloc(1, sizeof(LightBurnQuickLookPlugin));
    if (plugin == NULL) return NULL;

    QLGeneratorInterfaceStruct *table = malloc(sizeof(QLGeneratorInterfaceStruct));
    if (table == NULL) {
        free(plugin);
        return NULL;
    }
    memcpy(table, &gInterfaceTable, sizeof(QLGeneratorInterfaceStruct));

    plugin->conduitInterface = table;
    plugin->factoryID = CFRetain(factoryID);
    plugin->refCount = 1;
    CFPlugInAddInstanceForFactory(factoryID);
    return plugin;
}

void *QuickLookGeneratorPluginFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    (void)allocator;
    if (typeID == NULL || !CFEqual(typeID, kQLGeneratorTypeID)) return NULL;

    CFUUIDRef factoryID = CFUUIDCreateFromString(kCFAllocatorDefault, CFSTR(PLUGIN_ID));
    if (factoryID == NULL) return NULL;
    LightBurnQuickLookPlugin *plugin = AllocatePlugin(factoryID);
    CFRelease(factoryID);
    return plugin;
}
