// MoyuReader - macOS 摸鱼小说阅读器 (Objective-C 实现)
// 透明置顶 + 老板键(Option+H) + 章节跳转 + 自动翻页
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - 常量

#define DEFAULT_TOC_REGEX @"^\\s*(第\\s*[0-9０-９零一二两三四五六七八九十百千万〇]+\\s*[章节回卷部集]|Chapter\\s+\\d+|序章|楔子|引子|尾声|后记|番外)"

static NSString * const kTocRegex     = @"tocRegex";
static NSString * const kFontSize     = @"fontSize";
static NSString * const kOpacity      = @"opacity";
static NSString * const kAutoMode     = @"autoMode";
static NSString * const kAutoInterval = @"autoInterval";
static NSString * const kScrollSpeed  = @"scrollSpeed";
static NSString * const kLastBookPath = @"lastBookPath";

// AppDelegate 前置声明（热键回调需要）
@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
+ (AppDelegate *)shared;
- (void)toggleWindowVisible;
@end

#pragma mark - 可成为 Key 窗口的无边框窗口

@interface KeyWindow : NSWindow
@end
@implementation KeyWindow
- (BOOL)canBecomeKeyWindow { return YES; }
@end

#pragma mark - 目录弹窗控制器

@interface TOCViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray<NSNumber *> *offsets;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, copy) void (^onSelect)(NSInteger idx);
@end

@implementation TOCViewController {
    NSTableView *_table;
}

- (void)loadView {
    _table = [[NSTableView alloc] init];
    _table.dataSource = self;
    _table.delegate = self;
    _table.headerView = nil;
    _table.rowHeight = 24;
    _table.style = NSTableViewStylePlain;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:col];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 420)];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    [_table sizeLastColumnToFit];

    self.view = scroll;
    self.preferredContentSize = NSMakeSize(300, 420);
}

- (void)reloadWithCurrent:(NSInteger)current {
    self.currentIndex = current;
    [_table reloadData];
    if (current >= 0 && current < (NSInteger)_titles.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:current] byExtendingSelection:NO];
        [_table scrollRowToVisible:current];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _titles.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    NSTextField *label = [NSTextField labelWithString:_titles[row]];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.font = [NSFont systemFontOfSize:12];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-6],
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    if (row == self.currentIndex) label.textColor = [NSColor systemOrangeColor];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = _table.selectedRow;
    if (row >= 0 && row < (NSInteger)_titles.count && self.onSelect) {
        self.onSelect(row);
    }
}

@end

#pragma mark - 主内容视图（拖放）

@interface ReaderContentView : NSView
@property (nonatomic, copy) void (^onOpenFile)(NSURL *url);
@end

@implementation ReaderContentView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    return [pb canReadObjectForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}]
           ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
                                                             options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count == 0 || !self.onOpenFile) return NO;
    self.onOpenFile(urls.firstObject);
    return YES;
}

@end

#pragma mark - 文本视图（允许拖动窗口）与缩放手柄

@interface ReaderTextView : NSTextView
@property (nonatomic, assign) NSMenu *mainContextMenu; // 未选中文字时的右键菜单
@end
@implementation ReaderTextView
// 让「拖动文字区域 = 拖动窗口」全局生效
- (BOOL)mouseDownCanMoveWindow { return YES; }

// 右键菜单：选中了文字 → 复制/全选；否则 → 主菜单（全局生效）
- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.selectedRange.length > 0) {
        NSMenu *m = [[NSMenu alloc] init];
        NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"复制"
            action:@selector(copySelection:) keyEquivalent:@""];
        copyItem.target = self;
        [m addItem:copyItem];
        NSMenuItem *allItem = [[NSMenuItem alloc] initWithTitle:@"全选"
            action:@selector(selectAllText:) keyEquivalent:@""];
        allItem.target = self;
        [m addItem:allItem];
        return m;
    }
    return self.mainContextMenu;
}

- (void)copySelection:(id)sender  { [self copy:sender]; }
- (void)selectAllText:(id)sender  { [self selectAll:sender]; }
@end

// 边缘缩放手柄：贴右缘 / 底缘 / 右下角
@interface ResizeHandle : NSView
@property (nonatomic, assign) NSInteger edge; // 0=右缘 1=底缘 2=右下角
@end
@implementation ResizeHandle {
    NSRect _startFrame;
    CGPoint _startMouse;
}
- (BOOL)mouseDownCanMoveWindow { return NO; }

- (void)mouseDown:(NSEvent *)ev {
    _startFrame = self.window.frame;
    _startMouse = [NSEvent mouseLocation];
}

- (void)mouseDragged:(NSEvent *)ev {
    CGPoint now = [NSEvent mouseLocation];
    CGFloat dx = now.x - _startMouse.x;
    CGFloat dy = now.y - _startMouse.y;
    NSRect f = _startFrame;
    CGFloat newW = f.size.width, newH = f.size.height;
    if (self.edge == 0 || self.edge == 2) newW = MAX(320, f.size.width + dx);
    if (self.edge == 1 || self.edge == 2) newH = MAX(240, f.size.height - dy);
    CGFloat topY = f.origin.y + f.size.height;
    [self.window setFrame:NSMakeRect(f.origin.x, topY - newH, newW, newH) display:YES animate:NO];
}

- (void)resetCursorRects {
    NSCursor *c = [NSCursor resizeLeftRightCursor];
    if (self.edge == 1) c = [NSCursor resizeUpDownCursor];
    if (self.edge == 2) {
        if ([NSCursor respondsToSelector:@selector(resizeNorthWestSouthEastCursor)]) {
            c = [NSCursor performSelector:@selector(resizeNorthWestSouthEastCursor)];
        } else {
            c = [NSCursor crosshairCursor];
        }
    }
    [self addCursorRect:self.bounds cursor:c];
}
@end

#pragma mark - AppDelegate

@interface AppDelegate ()
{
    NSWindow *_window;
    NSScrollView *_scrollView;
    NSTextView *_textView;
    NSTextField *_statusLabel;
    CALayer *_bgLayer;
    NSPopover *_popover;
    TOCViewController *_tocVC;

    NSURL *_bookURL;
    NSString *_bookText;
    NSMutableArray<NSString *> *_chapterTitles;
    NSMutableArray<NSNumber *> *_chapterOffsets;
    NSInteger _currentChapter;

    NSTimer *_autoTimer;
    BOOL _autoRunning;
    BOOL _hoverPaused;
    NSDate *_lastSaveTime;
    NSDate *_lastChapterCalc;
    NSTimer *_statusTimer;
    NSStatusItem *_statusItem;

    EventHotKeyRef _hotKeyRef;
    EventHandlerRef _eventHandlerRef;
}
@end

static AppDelegate *_gDelegate = nil;

@implementation AppDelegate

- (NSWindow *)window { return _window; }
- (void)setWindow:(NSWindow *)w { _window = w; }

+ (AppDelegate *)shared { return _gDelegate; }

- (instancetype)init {
    self = [super init];
    if (self) {
        _chapterTitles = [NSMutableArray array];
        _chapterOffsets = [NSMutableArray array];
        _currentChapter = -1;
        _lastSaveTime = [NSDate distantPast];
    }
    return self;
}

#pragma mark 生命周期

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; // 无 Dock 图标
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kFontSize: @15.0,
        kOpacity: @0.0, // 默认全透明背景 + 黑字
        kAutoMode: @"scroll",
        kAutoInterval: @3.0,
        kScrollSpeed: @70.0,
    }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _gDelegate = self;

    [self setupWindow];
    [self setupContextMenu];
    [self setupStatusItem];
    [self registerGlobalHotKey];
    [self startStatusTimer];

    // 恢复上次的书
    NSString *lastPath = [[NSUserDefaults standardUserDefaults] stringForKey:kLastBookPath];
    if (lastPath.length > 0) {
        NSURL *url = [NSURL URLWithString:lastPath];
        if (url && [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
            [self loadBookWithURL:url restoreProgress:YES];
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self saveProgressForce:YES];
}

// 支持双击 TXT / 「打开方式」选择本 App
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if (![filename.pathExtension.lowercaseString isEqualToString:@"txt"] &&
        ![filename.pathExtension.lowercaseString isEqualToString:@"text"]) {
        return NO;
    }
    [self loadBookWithURL:[NSURL fileURLWithPath:filename] restoreProgress:YES];
    [NSApp activateIgnoringOtherApps:YES];
    return YES;
}

#pragma mark 设置读取

- (NSString *)tocRegex {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:kTocRegex];
    return s.length > 0 ? s : DEFAULT_TOC_REGEX;
}
- (void)setTocRegex:(NSString *)v {
    [[NSUserDefaults standardUserDefaults] setObject:v forKey:kTocRegex];
}
- (CGFloat)fontSize {
    return (CGFloat)[[NSUserDefaults standardUserDefaults] doubleForKey:kFontSize];
}
- (void)setFontSize:(CGFloat)v {
    [[NSUserDefaults standardUserDefaults] setDouble:(double)v forKey:kFontSize];
}
- (double)opacity {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:kOpacity];
}
- (void)setOpacity:(double)v {
    [[NSUserDefaults standardUserDefaults] setDouble:v forKey:kOpacity];
}
- (NSString *)autoMode {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:kAutoMode];
    return s.length > 0 ? s : @"scroll";
}
- (void)setAutoMode:(NSString *)v {
    [[NSUserDefaults standardUserDefaults] setObject:v forKey:kAutoMode];
}
- (double)autoInterval {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:kAutoInterval];
}
- (void)setAutoInterval:(double)v {
    [[NSUserDefaults standardUserDefaults] setDouble:v forKey:kAutoInterval];
}
- (double)scrollSpeed {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:kScrollSpeed];
}
- (void)setScrollSpeed:(double)v {
    [[NSUserDefaults standardUserDefaults] setDouble:v forKey:kScrollSpeed];
}

#pragma mark 窗口与界面

- (void)setupWindow {
    KeyWindow *w = [[KeyWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 520, 680)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                  NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered
        defer:NO];
    w.title = @"";
    w.titlebarAppearsTransparent = YES;           // 标题栏透明，融入内容
    w.titleVisibility = NSWindowTitleHidden;      // 不显示标题文字，只留红黄绿按钮
    w.opaque = NO;
    w.backgroundColor = [NSColor clearColor];
    w.hasShadow = NO;
    w.level = NSFloatingWindowLevel;
    w.movableByWindowBackground = YES;
    w.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                           NSWindowCollectionBehaviorFullScreenAuxiliary;
    [w center];
    self.window = w;

    // 红黄绿按钮默认隐藏，悬停窗口时显示
    [self setWindowButtonsHidden:YES];

    ReaderContentView *content = [[ReaderContentView alloc] initWithFrame:NSMakeRect(0, 0, 520, 680)];
    __weak typeof(self) weakSelf = self;
    content.onOpenFile = ^(NSURL *url) { [weakSelf loadBookWithURL:url restoreProgress:YES]; };
    w.contentView = content;

    content.wantsLayer = YES;
    _bgLayer = [CALayer layer];
    _bgLayer.cornerRadius = 8;
    content.layer = _bgLayer;
    [self applyBgAlpha];

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = NO; // 不要滚动条，滚轮/触控板滑动照常
    _scrollView.drawsBackground = NO;
    [content addSubview:_scrollView];

    ReaderTextView *tv = [[ReaderTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 600)];
    tv.editable = NO;
    tv.selectable = YES;
    tv.drawsBackground = NO;
    tv.textContainerInset = NSMakeSize(4, 8);
    tv.font = [self readerFont];
    tv.textColor = [NSColor colorWithWhite:0 alpha:0.85]; // 黑字，配合全透明背景
    tv.verticallyResizable = YES;
    tv.textContainer.widthTracksTextView = YES;
    tv.autoresizingMask = NSViewWidthSizable;
    _textView = tv;
    _scrollView.documentView = tv;
    // 大文档滚动性能：允许非连续布局（只布局可视区域附近）
    _textView.layoutManager.allowsNonContiguousLayout = YES;

    // 悬停暂停跟踪区（文字区）
    NSTrackingArea *tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:@{@"kind": @"hoverPause"}];
    [tv addTrackingArea:tracking];

    // 状态栏显隐跟踪区（整个窗口：悬停/点击显示，移出隐藏）
    NSTrackingArea *statusTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self userInfo:@{@"kind": @"statusBar"}];
    [content addTrackingArea:statusTracking];

    _statusLabel = [NSTextField labelWithString:@"拖入 TXT 文件开始阅读 · 右键打开菜单"];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor colorWithWhite:0 alpha:0.40];
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.hidden = YES; // 悬停/点击窗口时才显示
    [content addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:content.topAnchor constant:34], // 顶部留出红黄绿按钮区
        [_scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
        [_scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_statusLabel.topAnchor constant:-4],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-6],
        [_statusLabel.heightAnchor constraintEqualToConstant:16],
    ]];

    // 边缘缩放手柄（右缘 / 底缘 / 右下角），加在最后保证在最上层
    ResizeHandle *right = [[ResizeHandle alloc] initWithFrame:NSMakeRect(520 - 8, 0, 8, 680)];
    right.edge = 0;
    right.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    [content addSubview:right];
    ResizeHandle *bottom = [[ResizeHandle alloc] initWithFrame:NSMakeRect(0, 0, 520, 8)];
    bottom.edge = 1;
    bottom.autoresizingMask = NSViewMaxYMargin | NSViewWidthSizable;
    [content addSubview:bottom];
    ResizeHandle *corner = [[ResizeHandle alloc] initWithFrame:NSMakeRect(520 - 8, 0, 8, 8)];
    corner.edge = 2;
    corner.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:corner];

    // 文字颜色跟随背景：全透→黑字，有背景→白字
    [self applyTextColors];

    // 窗口缩放时强制文本视图宽度跟随 clip view（修复：缩放后文字不重新换行）
    _scrollView.contentView.postsFrameChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSViewFrameDidChangeNotification
        object:_scrollView.contentView
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) { [weakSelf syncTextViewWidth]; }];

    // TOC 弹窗
    _tocVC = [[TOCViewController alloc] init];
    _tocVC.onSelect = ^(NSInteger idx) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf jumpToChapter:idx];
        [strongSelf->_popover performClose:nil];
    };
    _popover = [[NSPopover alloc] init];
    _popover.behavior = NSPopoverBehaviorTransient;
    _popover.contentViewController = _tocVC;

        // 本地快捷键
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *ev) {
            return [weakSelf handleKeyDown:ev];
        }];
        // 点击显示状态栏 + 红黄绿；双击关闭窗口（Option+H 唤回）
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *ev) {
            if (ev.window != weakSelf.window) return ev;
            __strong typeof(weakSelf) strongSelf = weakSelf;
            NSPoint p = [strongSelf.window.contentView convertPoint:ev.locationInWindow fromView:nil];
            BOOL onButtons = (p.y > strongSelf.window.contentView.bounds.size.height - 34) && (p.x < 80);
            if (ev.clickCount >= 2 && !onButtons) {
                [strongSelf saveProgressForce:YES];
                strongSelf->_statusLabel.hidden = YES;
                [strongSelf setWindowButtonsHidden:YES];
                [strongSelf showWindowBorder:NO];
                [strongSelf.window orderOut:nil];
                return nil;
            }
            if (!onButtons) {
                strongSelf->_statusLabel.hidden = NO;
                [strongSelf setWindowButtonsHidden:NO];
                [strongSelf showWindowBorder:YES];
            }
            return ev;
        }];
    // 滚动结束保存进度
    [[NSNotificationCenter defaultCenter] addObserverForName:NSScrollViewDidEndLiveScrollNotification
        object:_scrollView queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) { [weakSelf saveProgressForce:NO]; }];

    [w makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSFont *)readerFont {
    NSFont *f = [NSFont fontWithName:@"PingFangSC-Regular" size:self.fontSize];
    return f ?: [NSFont systemFontOfSize:self.fontSize];
}

#pragma mark 右键菜单

- (void)setupContextMenu {
    NSMenu *m = [[NSMenu alloc] init];
    m.autoenablesItems = NO;
    [self addItem:m title:@"打开 TXT…" key:@"o" action:@selector(openFilePanel:)];
    [m addItem:[NSMenuItem separatorItem]];
    [self addItem:m title:@"章节目录" key:@"t" action:@selector(showTOC:)];
    [self addItem:m title:@"上一章" key:@"" action:@selector(prevChapter:)];
    [self addItem:m title:@"下一章" key:@"" action:@selector(nextChapter:)];
    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *autoItem = [self addItem:m title:@"开始自动阅读" key:@" " action:@selector(toggleAuto:)];
    autoItem.identifier = @"autoToggle";
    NSMenuItem *modeScroll = [self addItem:m title:@"自动模式：逐行滚动" key:@"" action:@selector(setModeScroll:)];
    modeScroll.identifier = @"modeScroll";
    NSMenuItem *modePage = [self addItem:m title:@"自动模式：整页翻页" key:@"" action:@selector(setModePage:)];
    modePage.identifier = @"modePage";

    NSMenu *speedMenu = [[NSMenu alloc] initWithTitle:@"滚动速度"];
    NSArray *speedNames = @[ @"慢", @"中", @"快" ];
    NSArray<NSNumber *> *speedVals = @[ @30, @70, @150 ];
    for (NSUInteger i = 0; i < speedNames.count; i++) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:speedNames[i] action:@selector(setSpeed:) keyEquivalent:@""];
        it.target = self;
        it.representedObject = speedVals[i];
        [speedMenu addItem:it];
    }
    NSMenuItem *speedItem = [[NSMenuItem alloc] initWithTitle:@"滚动速度" action:nil keyEquivalent:@""];
    speedItem.submenu = speedMenu;
    [m addItem:speedItem];

    NSMenu *intervalMenu = [[NSMenu alloc] initWithTitle:@"翻页间隔"];
    NSArray *intervals = @[ @"1 秒", @"2 秒", @"3 秒", @"5 秒" ];
    NSArray<NSNumber *> *intervalVals = @[ @1, @2, @3, @5 ];
    for (NSUInteger i = 0; i < intervals.count; i++) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:intervals[i] action:@selector(setInterval:) keyEquivalent:@""];
        it.target = self;
        it.representedObject = intervalVals[i];
        [intervalMenu addItem:it];
    }
    NSMenuItem *intervalItem = [[NSMenuItem alloc] initWithTitle:@"整页翻页间隔" action:nil keyEquivalent:@""];
    intervalItem.submenu = intervalMenu;
    [m addItem:intervalItem];
    [m addItem:[NSMenuItem separatorItem]];

    [self addItem:m title:@"字体放大" key:@"+" action:@selector(fontBigger:)];
    [self addItem:m title:@"字体缩小" key:@"-" action:@selector(fontSmaller:)];

    NSMenu *opacityMenu = [[NSMenu alloc] initWithTitle:@"窗口透明度"];
    NSArray *opNames = @[ @"全透（无背景）", @"更透", @"较透", @"适中", @"较实", @"更实" ];
    NSArray<NSNumber *> *opVals = @[ @0.0, @0.25, @0.40, @0.55, @0.70, @0.85 ];
    for (NSUInteger i = 0; i < opNames.count; i++) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:opNames[i] action:@selector(changeOpacity:) keyEquivalent:@""];
        it.target = self;
        it.representedObject = opVals[i];
        [opacityMenu addItem:it];
    }
    NSMenuItem *opacityItem = [[NSMenuItem alloc] initWithTitle:@"窗口透明度" action:nil keyEquivalent:@""];
    opacityItem.submenu = opacityMenu;
    [m addItem:opacityItem];
    [m addItem:[NSMenuItem separatorItem]];

    [self addItem:m title:@"目录正则设置…" key:@"" action:@selector(editRegex:)];
    [self addItem:m title:@"清除本书进度" key:@"" action:@selector(clearProgress:)];
    [m addItem:[NSMenuItem separatorItem]];
    [self addItem:m title:@"退出" key:@"q" action:@selector(quitApp:)];

    m.delegate = self;
    self.window.contentView.menu = m;                  // 边角区域兜底
    ((ReaderTextView *)_textView).mainContextMenu = m; // 文字区域：未选中时也弹主菜单
}

// 菜单栏右侧常驻图标：窗口关掉后从这里唤回
- (void)setupStatusItem {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    // SF Symbol 模板图标，和系统菜单栏其他图标风格一致（单色自适应）
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"book.fill"
                                  accessibilityDescription:@"摸鱼阅读器"];
    if (icon) {
        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium];
        icon = [icon imageWithSymbolConfiguration:cfg];
        icon.size = NSMakeSize(15, 15);
        icon.template = YES;
        _statusItem.button.image = icon;
    } else {
        _statusItem.button.title = @"📖";
    }
    _statusItem.button.toolTip = @"摸鱼阅读器";

    NSMenu *m = [[NSMenu alloc] init];
    NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:@"显示阅读窗口"
        action:@selector(toggleWindowVisible) keyEquivalent:@""];
    toggle.target = self;
    toggle.identifier = @"statusToggle";
    [m addItem:toggle];
    NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:@"打开 TXT…"
        action:@selector(openFilePanel:) keyEquivalent:@""];
    open.target = self;
    [m addItem:open];
    NSMenuItem *toc = [[NSMenuItem alloc] initWithTitle:@"章节目录"
        action:@selector(showTOC:) keyEquivalent:@""];
    toc.target = self;
    [m addItem:toc];
    [m addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出"
        action:@selector(quitApp:) keyEquivalent:@""];
    quit.target = self;
    [m addItem:quit];
    m.delegate = self;
    _statusItem.menu = m;
}

// 文字颜色跟随背景：全透（opacity=0）→ 黑字；有底色 → 白字
- (void)applyTextColors {
    BOOL transparent = self.opacity <= 0.001;
    if (_textView) {
        _textView.textColor = transparent
            ? [NSColor colorWithWhite:0 alpha:0.85]
            : [NSColor colorWithWhite:1 alpha:0.88];
    }
    if (_statusLabel) {
        _statusLabel.textColor = transparent
            ? [NSColor colorWithWhite:0 alpha:0.40]
            : [NSColor colorWithWhite:1 alpha:0.45];
    }
}

// 背景透明度：macOS 对无边框窗口做逐像素命中测试，alpha=0 的区域鼠标事件会直接
// 穿透到下层窗口（滚轮/点击全部失效）。所以「全透」实际用 2% 底色——肉眼不可见，
// 但能让 WindowServer 把事件判给本窗口。
- (CGFloat)effectiveBgAlpha {
    return (CGFloat)(1.0 / 255.0); // WindowServer 命中测试的最低可见 alpha
}

- (void)applyBgAlpha {
    _bgLayer.backgroundColor = [NSColor colorWithWhite:0 alpha:[self effectiveBgAlpha]].CGColor;
}

// 红黄绿按钮随点击显隐
- (void)setWindowButtonsHidden:(BOOL)hidden {
    [_window standardWindowButton:NSWindowCloseButton].hidden = hidden;
    [_window standardWindowButton:NSWindowMiniaturizeButton].hidden = hidden;
    [_window standardWindowButton:NSWindowZoomButton].hidden = hidden;
}

// 全透明时点击显示窗口边框，方便找到边界
- (void)showWindowBorder:(BOOL)show {
    if (!_bgLayer) return;
    _bgLayer.borderWidth = show ? 1.0 : 0.0;
    _bgLayer.borderColor = [NSColor colorWithWhite:0 alpha:0.55].CGColor;
}

// 缩放后让文本宽度强制跟随 clip view，触发重新换行
- (void)syncTextViewWidth {
    if (!_textView || !_scrollView || !_scrollView.contentView) return;
    CGFloat clipW = _scrollView.contentView.bounds.size.width;
    NSRect f = _textView.frame;
    if (fabs(f.size.width - clipW) < 0.5) return;
    f.size.width = clipW;
    [_textView setFrameSize:f.size];
    [_textView.layoutManager ensureLayoutForTextContainer:_textView.textContainer];
    [_textView sizeToFit];
}

- (NSMenuItem *)addItem:(NSMenu *)menu title:(NSString *)title key:(NSString *)key action:(SEL)action {
    NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    it.target = self;
    [menu addItem:it];
    return it;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    for (NSMenuItem *it in menu.itemArray) {
        NSString *idr = it.identifier;
        if ([idr isEqualToString:@"autoToggle"]) {
            it.title = _autoRunning ? @"停止自动阅读" : @"开始自动阅读";
        } else if ([idr isEqualToString:@"statusToggle"]) {
            it.title = self.window.isVisible ? @"隐藏阅读窗口" : @"显示阅读窗口";
        } else if ([idr isEqualToString:@"modeScroll"]) {
            it.state = [self.autoMode isEqualToString:@"scroll"] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([idr isEqualToString:@"modePage"]) {
            it.state = [self.autoMode isEqualToString:@"page"] ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
    for (NSMenuItem *it in menu.itemArray) {
        if ([it.title isEqualToString:@"滚动速度"] && it.submenu) {
            NSArray<NSNumber *> *vals = @[ @30, @70, @150 ];
            for (NSUInteger i = 0; i < it.submenu.numberOfItems; i++) {
                it.submenu.itemArray[i].state =
                    (self.scrollSpeed == vals[i].doubleValue) ? NSControlStateValueOn : NSControlStateValueOff;
            }
        }
        if ([it.title isEqualToString:@"整页翻页间隔"] && it.submenu) {
            NSArray<NSNumber *> *vals = @[ @1, @2, @3, @5 ];
            for (NSUInteger i = 0; i < it.submenu.numberOfItems; i++) {
                it.submenu.itemArray[i].state =
                    (self.autoInterval == vals[i].doubleValue) ? NSControlStateValueOn : NSControlStateValueOff;
            }
        }
        if ([it.title isEqualToString:@"窗口透明度"] && it.submenu) {
            NSArray<NSNumber *> *vals = @[ @0.0, @0.25, @0.40, @0.55, @0.70, @0.85 ];
            for (NSUInteger i = 0; i < it.submenu.numberOfItems; i++) {
                it.submenu.itemArray[i].state =
                    (self.opacity == vals[i].doubleValue) ? NSControlStateValueOn : NSControlStateValueOff;
            }
        }
    }
}

#pragma mark 打开与解析

- (void)openFilePanel:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[ UTTypePlainText ];
    [NSApp activateIgnoringOtherApps:YES];
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        [self loadBookWithURL:panel.URL restoreProgress:NO];
    }
}

- (void)loadBookWithURL:(NSURL *)url restoreProgress:(BOOL)restore {
    [self stopAuto];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) {
        [self updateStatus:[NSString stringWithFormat:@"无法读取文件：%@", url.lastPathComponent]];
        return;
    }

    NSString *encodingName = @"未知";
    NSString *text = [self decodeData:data encodingName:&encodingName];
    _bookText = text;
    _bookURL = url;
    [[NSUserDefaults standardUserDefaults] setObject:url.absoluteString forKey:kLastBookPath];

    _textView.string = text;
    [self applyFont];
    [self parseChapters];
    _tocVC.titles = _chapterTitles;
    _tocVC.offsets = _chapterOffsets;
    [_tocVC reloadWithCurrent:-1];

    NSMutableString *status = [NSMutableString stringWithFormat:@"%@ · %@ · %lu 章",
        url.lastPathComponent, encodingName, (unsigned long)_chapterTitles.count];
    if (_chapterTitles.count == 0) {
        [status appendString:@"（未识别到章节，可右键设置目录正则）"];
    }
    [self updateStatus:status];

    if (restore) {
        NSString *key = [@"progress." stringByAppendingString:url.path];
        double y = [[NSUserDefaults standardUserDefaults] doubleForKey:key];
        if (y > 0) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [weakSelf scrollToY:y]; });
        }
    }
    [self jumpToNearestChapter];
}

- (NSString *)decodeData:(NSData *)data encodingName:(NSString **)name {
    const unsigned char *bytes = data.bytes;
    NSUInteger len = data.length;

    if (len >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        NSString *s = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(3, len - 3)]
                                            encoding:NSUTF8StringEncoding];
        if (s) { if (name) *name = @"UTF-8"; return s; }
    }
    if (len >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        NSString *s = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, len - 2)]
                                            encoding:NSUTF16LittleEndianStringEncoding];
        if (s) { if (name) *name = @"UTF-16LE"; return s; }
    }
    if (len >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        NSString *s = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, len - 2)]
                                            encoding:NSUTF16BigEndianStringEncoding];
        if (s) { if (name) *name = @"UTF-16BE"; return s; }
    }
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s) { if (name) *name = @"UTF-8"; return s; }
    NSStringEncoding gbe = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    s = [[NSString alloc] initWithData:data encoding:gbe];
    if (s) { if (name) *name = @"GB18030"; return s; }
    if (name) *name = @"未知";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)parseChapters {
    [_chapterTitles removeAllObjects];
    [_chapterOffsets removeAllObjects];
    NSError *err = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:self.tocRegex
        options:NSRegularExpressionCaseInsensitive error:&err];
    if (!regex) return;

    NSString *text = _bookText;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
        options:NSStringEnumerationByLines
        usingBlock:^(NSString *line, NSRange lineRange, NSRange enclosingRange, BOOL *stop) {
            if (line.length == 0) return;
            NSRange found = [regex rangeOfFirstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
            if (found.location == NSNotFound) return;
            NSString *title = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (title.length <= 80) {
                [_chapterTitles addObject:title];
                // enclosingRange 覆盖「行 + 换行符」，location 即该行在全书的起始偏移（UTF-16 单位，
                // 与 NSTextView 的 NSRange 一致），不受重复章节名影响
                [_chapterOffsets addObject:@(enclosingRange.location)];
            }
        }];
}

#pragma mark 章节跳转

- (NSInteger)chapterIndexAtCharIndex:(NSInteger)charIdx {
    NSInteger lo = 0, hi = (NSInteger)_chapterOffsets.count - 1, ans = -1;
    while (lo <= hi) {
        NSInteger mid = (lo + hi) / 2;
        if (_chapterOffsets[mid].integerValue <= charIdx) { ans = mid; lo = mid + 1; }
        else hi = mid - 1;
    }
    return ans;
}

- (void)showTOC:(id)sender {
    if (_chapterTitles.count == 0) {
        [self updateStatus:@"未识别到章节，可右键 → 目录正则设置… 调整"];
        return;
    }
    [_tocVC reloadWithCurrent:_currentChapter];
    NSView *content = self.window.contentView;
    NSRect anchor = NSMakeRect(content.bounds.size.width / 2, 0, 1, 1);
    [_popover showRelativeToRect:anchor ofView:content preferredEdge:NSRectEdgeMaxY];
}

- (void)jumpToChapter:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)_chapterOffsets.count) return;
    _currentChapter = idx;
    [_textView scrollRangeToVisible:NSMakeRange(_chapterOffsets[idx].unsignedIntegerValue, 0)];
    [self refreshStatus];
    [self saveProgressForce:YES];
}

- (void)prevChapter:(id)sender {
    NSInteger idx = [self chapterIndexAtCharIndex:[self visibleCharIndex]];
    [self jumpToChapter:MAX(0, idx - 1)];
}

- (void)nextChapter:(id)sender {
    NSInteger idx = [self chapterIndexAtCharIndex:[self visibleCharIndex]];
    [self jumpToChapter:MIN((NSInteger)_chapterOffsets.count - 1, idx + 1)];
}

- (void)jumpToNearestChapter {
    _currentChapter = [self chapterIndexAtCharIndex:[self visibleCharIndex]];
}

#pragma mark 自动阅读

- (void)toggleAuto:(id)sender {
    if (_autoRunning) [self stopAuto]; else [self startAuto];
}

- (void)startAuto {
    if (_textView.string.length == 0) return;
    _autoRunning = YES;
    __weak typeof(self) weakSelf = self;
    if ([self.autoMode isEqualToString:@"scroll"]) {
        _autoTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
            [weakSelf autoScrollTick];
        }];
    } else {
        _autoTimer = [NSTimer scheduledTimerWithTimeInterval:self.autoInterval repeats:YES block:^(NSTimer *t) {
            [weakSelf autoPageTick];
        }];
        [self autoPageTick]; // 立即翻一页
    }
}

- (void)stopAuto {
    _autoRunning = NO;
    [_autoTimer invalidate];
    _autoTimer = nil;
}

- (void)autoScrollTick {
    if (_hoverPaused) return;
    double dy = self.scrollSpeed * 0.05;
    [self scrollToY:[self visibleY] + dy];
    if ([self visibleY] >= [self maxY] - 1) {
        [self stopAuto];
        [self updateStatus:@"已到文末"];
    }
    [self saveProgressForce:NO];
}

- (void)autoPageTick {
    if (_hoverPaused) return;
    double target = [self visibleY] + _scrollView.contentSize.height;
    [self scrollToY:target];
    if ([self visibleY] >= [self maxY] - 1) {
        [self stopAuto];
        [self updateStatus:@"已到文末"];
    }
    [self saveProgressForce:NO];
}

#pragma mark 滚动与进度

- (double)visibleY {
    return _scrollView.contentView.bounds.origin.y;
}

- (double)maxY {
    double docH = _scrollView.documentView ? _scrollView.documentView.bounds.size.height : 0;
    double visH = _scrollView.contentSize.height;
    return MAX(0, docH - visH);
}

- (void)scrollToY:(double)y {
    double clamped = MIN(MAX(0, y), [self maxY]);
    [_scrollView.contentView scrollToPoint:NSMakePoint(0, clamped)];
    [_scrollView reflectScrolledClipView:_scrollView.contentView];
}

- (NSInteger)visibleCharIndex {
    double y = _scrollView.contentView.bounds.origin.y + _textView.textContainerInset.height;
    NSPoint point = NSMakePoint(_textView.textContainerInset.width + 2, MAX(0, y));
    return (NSInteger)[_textView.layoutManager characterIndexForPoint:point
                                                      inTextContainer:_textView.textContainer
                                      fractionOfDistanceBetweenInsertionPoints:NULL];
}

- (void)saveProgressForce:(BOOL)force {
    if (!_bookURL) return;
    NSDate *now = [NSDate date];
    if (!force && [now timeIntervalSinceDate:_lastSaveTime] < 1.0) return;
    _lastSaveTime = now;
    NSString *key = [@"progress." stringByAppendingString:_bookURL.path];
    [[NSUserDefaults standardUserDefaults] setDouble:[self visibleY] forKey:key];
}

- (void)clearProgress:(id)sender {
    if (!_bookURL) return;
    NSString *key = [@"progress." stringByAppendingString:_bookURL.path];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [self scrollToY:0];
    [self jumpToNearestChapter];
}

#pragma mark 状态栏

- (void)startStatusTimer {
    __weak typeof(self) weakSelf = self;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        [weakSelf refreshStatus];
    }];
}

- (void)refreshStatus {
    if (!_bookURL) return;
    double y = [self visibleY];
    double total = [self maxY];
    int pct = total > 0 ? (int)round(y / total * 100) : 0;
    // 章节定位（characterIndexForPoint）开销大，最多每 2 秒算一次
    NSDate *now = [NSDate date];
    if (!_lastChapterCalc || [now timeIntervalSinceDate:_lastChapterCalc] >= 2.0) {
        _lastChapterCalc = now;
        _currentChapter = [self chapterIndexAtCharIndex:[self visibleCharIndex]];
    }
    NSInteger idx = _currentChapter;
    NSString *chapterName = (idx >= 0 && idx < (NSInteger)_chapterTitles.count) ? _chapterTitles[idx] : @"正文";
    NSString *hoverNote = (_autoRunning && _hoverPaused) ? @" · 悬停暂停中" : @"";
    [self updateStatus:[NSString stringWithFormat:@"%@ · %d%%%@", chapterName, pct, hoverNote]];
}

- (void)updateStatus:(NSString *)s {
    _statusLabel.stringValue = s;
}

#pragma mark 设置动作

- (void)setModeScroll:(id)sender {
    self.autoMode = @"scroll";
    if (_autoRunning) { [self stopAuto]; [self startAuto]; }
}
- (void)setModePage:(id)sender {
    self.autoMode = @"page";
    if (_autoRunning) { [self stopAuto]; [self startAuto]; }
}
- (void)setSpeed:(NSMenuItem *)sender {
    self.scrollSpeed = [(NSNumber *)sender.representedObject doubleValue];
}
- (void)setInterval:(NSMenuItem *)sender {
    self.autoInterval = [(NSNumber *)sender.representedObject doubleValue];
    if (_autoRunning && [self.autoMode isEqualToString:@"page"]) { [self stopAuto]; [self startAuto]; }
}
- (void)changeOpacity:(NSMenuItem *)sender {
    self.opacity = [(NSNumber *)sender.representedObject doubleValue];
    [self applyBgAlpha];
    [self applyTextColors];
}
- (void)fontBigger:(id)sender {
    self.fontSize = MIN(30, self.fontSize + 1);
    [self applyFont];
}
- (void)fontSmaller:(id)sender {
    self.fontSize = MAX(10, self.fontSize - 1);
    [self applyFont];
}

- (void)applyFont {
    NSFont *font = [self readerFont];
    _textView.font = font;
    if (_textView.textStorage.length > 0) {
        [_textView.textStorage addAttribute:NSFontAttributeName value:font
            range:NSMakeRange(0, _textView.textStorage.length)];
    }
}

- (void)editRegex:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"目录解析正则";
    alert.informativeText = @"匹配到的行会作为章节标题。默认：第…章 开头";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 380, 24)];
    input.stringValue = self.tocRegex;
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        self.tocRegex = input.stringValue;
        [self parseChapters];
        _tocVC.titles = _chapterTitles;
        _tocVC.offsets = _chapterOffsets;
        [_tocVC reloadWithCurrent:_currentChapter];
        [self updateStatus:[NSString stringWithFormat:@"目录已重新解析：%lu 章", (unsigned long)_chapterTitles.count]];
    }
}

#pragma mark 老板键（Option+H 全局热键）

static OSStatus hotKeyHandler(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData) {
    [[AppDelegate shared] toggleWindowVisible];
    return noErr;
}

- (void)registerGlobalHotKey {
    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'MOYU';
    hotKeyID.id = 1;
    OSStatus status = RegisterEventHotKey((UInt32)kVK_ANSI_H, (UInt32)optionKey,
                                          hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);
    if (status != noErr) {
        NSLog(@"MoyuReader: 全局热键注册失败 %d", (int)status);
        return;
    }
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    InstallEventHandler(GetApplicationEventTarget(),
                        NewEventHandlerUPP(hotKeyHandler), 1, &eventType, NULL, &_eventHandlerRef);
}

- (void)toggleWindowVisible {
    if (_window.isMiniaturized) {
        // 最小化按钮收起的窗口：先 deminiaturize
        [_window deminiaturize:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [_window makeKeyAndOrderFront:nil];
    } else if (_window.isVisible) {
        [self saveProgressForce:YES];
        [NSApp hide:nil];
    } else {
        [NSApp unhide:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [_window makeKeyAndOrderFront:nil];
    }
}

#pragma mark 快捷键

- (NSEvent *)handleKeyDown:(NSEvent *)ev {
    if (!(self.window.isKeyWindow || self.window.isVisible)) return ev;
    NSEventModifierFlags flags = ev.modifierFlags;
    BOOL cmd = (flags & NSEventModifierFlagCommand) != 0;
    switch (ev.keyCode) {
        case 49: // Space
            if (!cmd) { [self toggleAuto:nil]; return nil; }
            break;
        case 53: // Esc
            if (_popover.isShown) { [_popover performClose:nil]; return nil; }
            break;
        case 31: if (cmd) { [self openFilePanel:nil]; return nil; } break; // Cmd+O
        case 17: if (cmd) { [self showTOC:nil]; return nil; } break;       // Cmd+T
        case 123: if (cmd) { [self prevChapter:nil]; return nil; } break;  // Cmd+←
        case 124: if (cmd) { [self nextChapter:nil]; return nil; } break;  // Cmd+→
        case 24: if (cmd) { [self fontBigger:nil]; return nil; } break;    // Cmd+=
        case 27: if (cmd) { [self fontSmaller:nil]; return nil; } break;   // Cmd+-
        case 12: if (cmd) { [self quitApp:nil]; return nil; } break;       // Cmd+Q
        default: break;
    }
    return ev;
}

- (void)quitApp:(id)sender {
    [self saveProgressForce:YES];
    [NSApp terminate:nil];
}

#pragma mark 悬停事件（状态栏显隐 + 自动阅读悬停暂停）

- (void)mouseEntered:(NSEvent *)event {
    NSString *kind = event.trackingArea.userInfo[@"kind"];
    if (![kind isEqualToString:@"statusBar"]) {
        _hoverPaused = YES; // 悬停暂停自动阅读
    }
}

- (void)mouseExited:(NSEvent *)event {
    NSString *kind = event.trackingArea.userInfo[@"kind"];
    if ([kind isEqualToString:@"statusBar"]) {
        _statusLabel.hidden = YES;
        [self setWindowButtonsHidden:YES];
        [self showWindowBorder:NO];
    } else {
        _hoverPaused = NO;
    }
}

@end

#pragma mark - 启动

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
