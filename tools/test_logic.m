// MoyuReader 逻辑回归测试：直接 #import 源文件，保证测的就是真实实现
// clang -fobjc-arc tools/test_logic.m -o build/test_logic -framework AppKit -framework Carbon -framework QuartzCore -framework UniformTypeIdentifiers
#define main moyu_unused_main
#import "../Sources/main.m"
#undef main
#import <Foundation/Foundation.h>

static int gPass = 0, gFail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { gPass++; } \
    else { gFail++; NSLog(@"FAIL: %s — %@", #cond, msg); } \
} while (0)

int main(void) {
    @autoreleasepool {
        AppDelegate *app = [[AppDelegate alloc] init];

        // ===== 1. 编码识别 =====
        NSString *name = nil;
        NSString *s = nil;

        // UTF-8 无 BOM
        NSData *u8 = [@"第一章 开端\n正文内容" dataUsingEncoding:NSUTF8StringEncoding];
        s = [app decodeData:u8 encodingName:&name];
        CHECK([s isEqualToString:@"第一章 开端\n正文内容"], s);
        CHECK([name isEqualToString:@"UTF-8"], name);

        // UTF-8 BOM
        NSMutableData *u8bom = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [u8bom appendData:[@"你好" dataUsingEncoding:NSUTF8StringEncoding]];
        s = [app decodeData:u8bom encodingName:&name];
        CHECK([s isEqualToString:@"你好"], s);
        CHECK([name isEqualToString:@"UTF-8"], name);

        // GB18030（中文常见编码）
        NSStringEncoding gbe = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
        NSData *gb = [@"第一章 试炼\n风起云涌" dataUsingEncoding:gbe];
        s = [app decodeData:gb encodingName:&name];
        CHECK([s isEqualToString:@"第一章 试炼\n风起云涌"], s);
        CHECK([name isEqualToString:@"GB18030"], name);

        // ===== 2. 章节解析（30 章 + 尾声） =====
        NSMutableString *book = [NSMutableString string];
        [book appendString:@"开头没有章节标记的一段\n"];
        for (int i = 1; i <= 30; i++) {
            [book appendFormat:@"第%d章 章节%d\n", i, i];
            for (int j = 0; j < 5; j++) [book appendString:@"这里是正文内容，模拟一段小说文字。\n"];
        }
        [book appendString:@"尾声\n最后一行"];

        [app setValue:book forKey:@"bookText"];
        [app parseChapters];

        NSArray *titles = [app valueForKey:@"chapterTitles"];
        NSArray *offsets = [app valueForKey:@"chapterOffsets"];
        CHECK(titles.count == 31, titles);       // 30 章 + 尾声
        CHECK(offsets.count == 31, offsets);

        // 第一章标题正确、偏移落在「第」字上
        CHECK([titles[0] isEqualToString:@"第1章 章节1"], titles[0]);
        NSUInteger off0 = [offsets[0] unsignedIntegerValue];
        CHECK([book hasPrefix:@"开头"], @YES);
        CHECK([[book substringWithRange:NSMakeRange(off0, 3)] isEqualToString:@"第1章"], @(off0));

        // 尾声被识别
        CHECK([titles.lastObject isEqualToString:@"尾声"], titles.lastObject);

        // ===== 3. 章节二分查找 =====
        NSInteger idx = [app chapterIndexAtCharIndex:(NSInteger)off0 + 10];
        CHECK(idx == 0, @(idx));
        NSUInteger lastOff = [offsets[30] unsignedIntegerValue];
        NSInteger idx2 = [app chapterIndexAtCharIndex:(NSInteger)lastOff + 3];
        CHECK(idx2 == 30, @(idx2));
        NSInteger idx3 = [app chapterIndexAtCharIndex:0];
        CHECK(idx3 == -1, @(idx3)); // 开头还没进第一章

        // ===== 4. 无章节的书 =====
        NSString *plain = @"没有章节标记的书\n第二行";
        [app setValue:plain forKey:@"bookText"];
        [app parseChapters];
        NSArray *titles2 = [app valueForKey:@"chapterTitles"];
        CHECK(titles2.count == 0, titles2);

        // ===== 5. 默认正则可编译 =====
        NSError *err = nil;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:DEFAULT_TOC_REGEX
            options:NSRegularExpressionCaseInsensitive error:&err];
        CHECK(re != nil, err);

        NSLog(@"\n测试结果: %d 通过, %d 失败", gPass, gFail);
        return gFail == 0 ? 0 : 1;
    }
}
