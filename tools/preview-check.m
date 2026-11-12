#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
static void Dump(NSView *v, int depth) {
    printf("%*s%s %.0fx%.0f\n", depth*2, "", class_getName([v class]), v.bounds.size.width, v.bounds.size.height);
    for(NSView *s in v.subviews) Dump(s, depth+1);
}
// Visual diagnostic: exercise the actual Quick Look renderer, then save its window.
int main(int argc, const char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: preview-check PROJECT_FILE SCREENSHOT.png\n");
        return 2;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:argv[1]]]) {
        fprintf(stderr, "Input file does not exist.\n");
        return 2;
    }
    @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,600,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    QLPreviewView *view = [[QLPreviewView alloc] initWithFrame:NSMakeRect(0,0,600,600) style:QLPreviewViewStyleNormal];
    window.contentView=view;
    view.autostarts=YES;
    view.previewItem=(id<QLPreviewItem>)[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];
    while([end timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    Dump(view,0);
    CGImageRef shot=CGWindowListCreateImage(CGRectNull,kCGWindowListOptionIncludingWindow,(CGWindowID)window.windowNumber,kCGWindowImageBoundsIgnoreFraming);
    if(shot){ NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:shot]; [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES]; CGImageRelease(shot); }
    if (shot == NULL) { fprintf(stderr, "Window capture failed.\n"); [view close]; return 1; }
    [view close];
    [window orderOut:nil];
} return 0; }
