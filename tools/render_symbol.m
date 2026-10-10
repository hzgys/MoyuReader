// 渲染 SF Symbol 到透明 PNG：render_symbol <symbol名> <输出png> <画布size> <pointSize>
// clang -fobjc-arc render_symbol.m -o render_symbol -framework AppKit
#import <AppKit/AppKit.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 5) { fprintf(stderr, "usage: %s symbol out.png size pointSize\n", argv[0]); return 1; }
        NSString *name = [NSString stringWithUTF8String:argv[1]];
        CGFloat size = atof(argv[3]);
        CGFloat pointSize = atof(argv[4]);

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *symbol = [NSImage imageWithSystemSymbolName:name
                                      accessibilityDescription:nil];
        if (!symbol) { fprintf(stderr, "symbol not found: %s\n", argv[1]); return 2; }
        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightRegular];
        symbol = [symbol imageWithSymbolConfiguration:cfg];

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size pixelsHigh:(NSInteger)size
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [rep setSize:NSMakeSize(size, size)];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext setCurrentContext:ctx];

        NSSize sz = symbol.size;
        NSPoint origin = NSMakePoint((size - sz.width) / 2.0, (size - sz.height) / 2.0);
        [symbol drawInRect:NSMakeRect(origin.x, origin.y, sz.width, sz.height)
              fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
        printf("OK %s (%.0fx%.0f)\n", argv[2], sz.width, sz.height);
    }
    return 0;
}
