// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Cocoa/Cocoa.h>

#include "base/basictypes.h"
#include "base/scoped_nsobject.h"
#import "chrome/browser/cocoa/bookmark_bar_constants.h"  // namespace bookmarks
#import "chrome/browser/cocoa/bookmark_bar_controller.h"
#import "chrome/browser/cocoa/bookmark_bar_folder_button_cell.h"
#import "chrome/browser/cocoa/bookmark_bar_folder_controller.h"
#import "chrome/browser/cocoa/bookmark_bar_unittest_helper.h"
#include "chrome/browser/cocoa/browser_test_helper.h"
#import "chrome/browser/cocoa/cocoa_test_helper.h"
#import "chrome/browser/cocoa/view_resizer_pong.h"
#include "chrome/test/model_test_utils.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "testing/platform_test.h"

// Add a redirect to make testing easier.
@interface BookmarkBarFolderController(MakeTestingEasier)
- (IBAction)openBookmarkFolderFromButton:(id)sender;
@end

@implementation BookmarkBarFolderController(MakeTestingEasier)
- (IBAction)openBookmarkFolderFromButton:(id)sender {
  [[self folderTarget] openBookmarkFolderFromButton:sender];
}
@end

// Don't use a high window level when running unit tests -- it'll
// interfere with anything else you are working on.
@interface BookmarkBarFolderControllerLow : BookmarkBarFolderController {
  BOOL realTopLeft_;  // Use the real windowTopLeft call?
}
@property (nonatomic) BOOL realTopLeft;
@end


@implementation BookmarkBarFolderControllerLow

@synthesize realTopLeft = realTopLeft_;

- (void)configureWindowLevel {
  // Intentionally empty.
}

- (NSPoint)windowTopLeft {
  return realTopLeft_ ? [super windowTopLeft] : NSMakePoint(200,200);
}

@end


@interface BookmarkBarFolderControllerPong : BookmarkBarFolderControllerLow {
  BOOL childFolderWillShow_;
  BOOL childFolderWillClose_;
}
@property (nonatomic, readonly) BOOL childFolderWillShow;
@property (nonatomic, readonly) BOOL childFolderWillClose;
@end

@implementation BookmarkBarFolderControllerPong
@synthesize childFolderWillShow = childFolderWillShow_;
@synthesize childFolderWillClose = childFolderWillClose_;

- (void)childFolderWillShow:(id<BookmarkButtonControllerProtocol>)child {
  childFolderWillShow_ = YES;
}

- (void)childFolderWillClose:(id<BookmarkButtonControllerProtocol>)child {
  childFolderWillClose_ = YES;
}

// We don't have a real BookmarkBarController as our parent root so
// we fake this one out.
- (void)closeAllBookmarkFolders {
  [self closeBookmarkFolder:self];
}

@end

namespace {
const int kLotsOfNodesCount = 150;
};

class BookmarkBarFolderControllerTest : public CocoaTest {
 public:
  BrowserTestHelper helper_;
  scoped_nsobject<BookmarkBarController> parentBarController_;
  const BookmarkNode* folderA_;  // owned by model
  const BookmarkNode* longTitleNode_;  // owned by model

  BookmarkBarFolderControllerTest() {
    BookmarkModel* model = helper_.profile()->GetBookmarkModel();
    const BookmarkNode* parent = model->GetBookmarkBarNode();
    const BookmarkNode* folderA = model->AddGroup(parent,
                                                  parent->GetChildCount(),
                                                  L"group");
    folderA_ = folderA;
    model->AddGroup(parent, parent->GetChildCount(),
                    L"sibbling group");
    const BookmarkNode* folderB = model->AddGroup(folderA,
                                                  folderA->GetChildCount(),
                                                  L"subgroup 1");
    model->AddGroup(folderA,
                    folderA->GetChildCount(),
                    L"subgroup 2");
    model->AddURL(folderA, folderA->GetChildCount(), L"title a",
                  GURL("http://www.google.com/a"));
    longTitleNode_ = model->AddURL(
      folderA, folderA->GetChildCount(),
      L"title super duper long long whoa momma title you betcha",
      GURL("http://www.google.com/b"));
    model->AddURL(folderB, folderB->GetChildCount(), L"t",
                  GURL("http://www.google.com/c"));

    parentBarController_.reset(
      [[BookmarkBarController alloc]
          initWithBrowser:helper_.browser()
             initialWidth:300
                 delegate:nil
           resizeDelegate:nil]);
    [parentBarController_ loaded:model];
    [[test_window() contentView] addSubview:[parentBarController_ view]];
  }

  // Remove the bookmark with the long title.
  void RemoveLongTitleNode() {
    BookmarkModel* model = helper_.profile()->GetBookmarkModel();
    model->Remove(longTitleNode_->GetParent(),
                  longTitleNode_->GetParent()->IndexOfChild(longTitleNode_));
  }

  // Add LOTS of nodes to our model if needed (e.g. scrolling).
  // Returns the number of nodes added.
  int AddLotsOfNodes() {
    BookmarkModel* model = helper_.profile()->GetBookmarkModel();
    for (int i = 0; i < kLotsOfNodesCount; i++) {
      model->AddURL(folderA_, folderA_->GetChildCount(), L"repeated title",
                    GURL("http://www.google.com/repeated/url"));
    }
    return kLotsOfNodesCount;
  }


  // Return a simple BookmarkBarFolderController.
  BookmarkBarFolderController* SimpleBookmarkBarFolderController() {
    BookmarkButton* parentButton = [[parentBarController_ buttons]
                                     objectAtIndex:0];
    BookmarkBarFolderController* c =
      [[BookmarkBarFolderControllerPong alloc]
               initWithParentButton:parentButton
                   parentController:nil
                      barController:parentBarController_];
    [c window];  // Force nib load.
    return c;
  }
};

TEST_F(BookmarkBarFolderControllerTest, InitCreateAndDelete) {
  scoped_nsobject<BookmarkBarFolderController> bbfc;
  bbfc.reset(SimpleBookmarkBarFolderController());

  // Make sure none of the buttons overlap, that all are inside
  // the content frame, and their cells are of the proper class.
  NSArray* buttons = [bbfc buttons];
  EXPECT_TRUE([buttons count]);
  for (unsigned int i = 0; i < ([buttons count]-1); i++) {
    EXPECT_FALSE(NSContainsRect([[buttons objectAtIndex:i] frame],
                              [[buttons objectAtIndex:i+1] frame]));
  }
  Class cellClass = [BookmarkBarFolderButtonCell class];
  for (BookmarkButton* button in buttons) {
    NSRect r = [[bbfc mainView] convertRect:[button frame] fromView:button];
    EXPECT_TRUE(NSContainsRect([[bbfc mainView] frame], r));
    EXPECT_TRUE([[button cell] isKindOfClass:cellClass]);
  }

  // Confirm folder buttons have no tooltip.  The important thing
  // really is that we insure folders and non-folders are treated
  // differently; not sure of any other generic way to do this.
  for (BookmarkButton* button in buttons) {
    if ([button isFolder])
      EXPECT_FALSE([button toolTip]);
    else
      EXPECT_TRUE([button toolTip]);
  }
}

// Make sure closing of the window releases the controller.
// (e.g. valgrind shouldn't complain if we do this).
TEST_F(BookmarkBarFolderControllerTest, ReleaseOnClose) {
  scoped_nsobject<BookmarkBarFolderController> bbfc;
  bbfc.reset(SimpleBookmarkBarFolderController());
  EXPECT_TRUE(bbfc.get());

  [bbfc retain];  // stop the scoped_nsobject from doing anything
  [[bbfc window] close];  // trigger an autorelease of bbfc.get()
}

TEST_F(BookmarkBarFolderControllerTest, Position) {
 BookmarkButton* parentButton = [[parentBarController_ buttons]
                                   objectAtIndex:0];
  EXPECT_TRUE(parentButton);

  // If parent is a BookmarkBarController, grow down.
  scoped_nsobject<BookmarkBarFolderControllerLow> bbfc;
  bbfc.reset([[BookmarkBarFolderControllerLow alloc]
               initWithParentButton:parentButton
                   parentController:nil
                      barController:parentBarController_]);
  [bbfc window];
  [bbfc setRealTopLeft:YES];
  NSPoint pt = [bbfc windowTopLeft];  // screen coords
  NSPoint buttonOriginInScreen =
      [[parentButton window]
        convertBaseToScreen:[parentButton
                              convertRectToBase:[parentButton frame]].origin];
  // Within margin
  EXPECT_LE(abs(pt.x - buttonOriginInScreen.x), 2);
  EXPECT_LE(abs(pt.y - buttonOriginInScreen.y), 2);

  // If parent is a BookmarkBarFolderController, grow right.
  scoped_nsobject<BookmarkBarFolderControllerLow> bbfc2;
  bbfc2.reset([[BookmarkBarFolderControllerLow alloc]
                initWithParentButton:[[bbfc buttons] objectAtIndex:0]
                    parentController:bbfc.get()
                       barController:parentBarController_]);
  [bbfc2 window];
  [bbfc2 setRealTopLeft:YES];
  pt = [bbfc2 windowTopLeft];
  // We're now overlapping the window a bit.
  EXPECT_EQ(pt.x, NSMaxX([[bbfc.get() window] frame]) -
            bookmarks::kBookmarkMenuOverlap);
}

TEST_F(BookmarkBarFolderControllerTest, DropDestination) {
  scoped_nsobject<BookmarkBarFolderController> bbfc;
  bbfc.reset(SimpleBookmarkBarFolderController());
  EXPECT_TRUE(bbfc.get());

  // Confirm "off the top" and "off the bottom" match no buttons.
  NSPoint p = NSMakePoint(NSMidX([[bbfc mainView] frame]), 10000);
  EXPECT_FALSE([bbfc buttonForDroppingOnAtPoint:p]);
  EXPECT_TRUE([bbfc shouldShowIndicatorShownForPoint:p]);
  p = NSMakePoint(NSMidX([[bbfc mainView] frame]), -1);
  EXPECT_FALSE([bbfc buttonForDroppingOnAtPoint:p]);
  EXPECT_TRUE([bbfc shouldShowIndicatorShownForPoint:p]);

  // Confirm "right in the center" (give or take a pixel) is a match,
  // and confirm "just barely in the button" is not.  Anything more
  // specific seems likely to be tweaked.  We don't loop over all
  // buttons because the scroll view makes them not visible.
  for (BookmarkButton* button in [bbfc buttons]) {
    CGFloat x = NSMidX([button frame]);
    CGFloat y = NSMidY([button frame]);
    // Somewhere near the center: a match (but only if a folder!)
    if ([button isFolder]) {
      EXPECT_EQ(button,
                [bbfc buttonForDroppingOnAtPoint:NSMakePoint(x-1, y+1)]);
      EXPECT_EQ(button,
                [bbfc buttonForDroppingOnAtPoint:NSMakePoint(x+1, y-1)]);
      EXPECT_FALSE([bbfc shouldShowIndicatorShownForPoint:NSMakePoint(x, y)]);;
    } else {
      // If not a folder we don't drop into it.
      EXPECT_FALSE([bbfc buttonForDroppingOnAtPoint:NSMakePoint(x-1, y+1)]);
      EXPECT_FALSE([bbfc buttonForDroppingOnAtPoint:NSMakePoint(x+1, y-1)]);
      EXPECT_TRUE([bbfc shouldShowIndicatorShownForPoint:NSMakePoint(x, y)]);;
    }
  }
}

TEST_F(BookmarkBarFolderControllerTest, OpenFolder) {
  scoped_nsobject<BookmarkBarFolderController> bbfc;
  bbfc.reset(SimpleBookmarkBarFolderController());
  EXPECT_TRUE(bbfc.get());

  EXPECT_FALSE([bbfc folderController]);
  BookmarkButton* button = [[bbfc buttons] objectAtIndex:0];
  [bbfc openBookmarkFolderFromButton:button];
  id controller = [bbfc folderController];
  EXPECT_TRUE(controller);
  EXPECT_EQ([controller parentButton], button);

  // Click the same one --> it gets closed.
  [bbfc openBookmarkFolderFromButton:[[bbfc buttons] objectAtIndex:0]];
  EXPECT_FALSE([bbfc folderController]);

  // Open a new one --> change.
  [bbfc openBookmarkFolderFromButton:[[bbfc buttons] objectAtIndex:1]];
  EXPECT_NE(controller, [bbfc folderController]);
  EXPECT_NE([[bbfc folderController] parentButton], button);

  // Close it --> all gone!
  [bbfc closeBookmarkFolder:nil];
  EXPECT_FALSE([bbfc folderController]);
}

TEST_F(BookmarkBarFolderControllerTest, ChildFolderCallbacks) {
  scoped_nsobject<BookmarkBarFolderControllerPong> bbfc;
  bbfc.reset(SimpleBookmarkBarFolderController());
  EXPECT_TRUE(bbfc.get());

  EXPECT_FALSE([bbfc childFolderWillShow]);
  [bbfc openBookmarkFolderFromButton:[[bbfc buttons] objectAtIndex:0]];
  EXPECT_TRUE([bbfc childFolderWillShow]);

  EXPECT_FALSE([bbfc childFolderWillClose]);
  [bbfc closeBookmarkFolder:nil];
  EXPECT_TRUE([bbfc childFolderWillClose]);
}

// Make sure bookmark folders have variable widths.
TEST_F(BookmarkBarFolderControllerTest, ChildFolderWidth) {
  scoped_nsobject<BookmarkBarFolderController> bbfc;

  bbfc.reset(SimpleBookmarkBarFolderController());
  EXPECT_TRUE(bbfc.get());
  [bbfc showWindow:bbfc.get()];
  CGFloat wideWidth = NSWidth([[bbfc window] frame]);

  RemoveLongTitleNode();
  bbfc.reset(SimpleBookmarkBarFolderController());
  EXPECT_TRUE(bbfc.get());
  CGFloat thinWidth = NSWidth([[bbfc window] frame]);

  // Make sure window size changed as expected.
  EXPECT_GT(wideWidth, thinWidth);
}

// Simple scrolling tests.
TEST_F(BookmarkBarFolderControllerTest, SimpleScroll) {
  scoped_nsobject<BookmarkBarFolderController> bbfc;

  int nodecount = AddLotsOfNodes();
  bbfc.reset(SimpleBookmarkBarFolderController());
  EXPECT_TRUE(bbfc.get());
  [bbfc showWindow:bbfc.get()];

  // Make sure the window fits on the screen.
  EXPECT_LT(NSHeight([[bbfc window] frame]),
            NSHeight([[NSScreen mainScreen] frame]));

  // Verify the logic used by the scroll arrow code.
  EXPECT_TRUE([bbfc canScrollUp]);
  EXPECT_FALSE([bbfc canScrollDown]);

  // Scroll it up.  Make sure the window has gotten bigger each time.
  // Also, for each scroll, make sure our hit test finds a new button
  // (to confirm the content area changed).
  NSView* savedHit = nil;
  for (int i=0; i<3; i++) {
    CGFloat height = NSHeight([[bbfc window] frame]);
    [bbfc performOneScroll:60];
    EXPECT_GT(NSHeight([[bbfc window] frame]), height);
    NSView* hit = [[[bbfc window] contentView] hitTest:NSMakePoint(22, 22)];
    EXPECT_NE(hit, savedHit);
    savedHit = hit;
  }

  // Keep scrolling up; make sure we never get bigger than the screen.
  // Also confirm we never scroll the window off the screen.
  bool bothAtOnce = false;
  NSRect screenFrame = [[NSScreen mainScreen] frame];
  for (int i = 0; i < nodecount; i++) {
    [bbfc performOneScroll:60];
    EXPECT_TRUE(NSContainsRect(screenFrame,
                               [[bbfc window] frame]));
    // Make sure, sometime during our scroll, we have the ability to
    // scroll in either direction.
    if ([bbfc canScrollUp] &&
        [bbfc canScrollDown])
      bothAtOnce = true;
  }
  EXPECT_TRUE(bothAtOnce);

  // Once we've scrolled to the end, our only option should be to scroll back.
  EXPECT_FALSE([bbfc canScrollUp]);
  EXPECT_TRUE([bbfc canScrollDown]);

  // Now scroll down and make sure the window size does not change.
  // Also confirm we never scroll the window off the screen the other
  // way.
  for (int i=0; i<nodecount+50; i++) {
    CGFloat height = NSHeight([[bbfc window] frame]);
    [bbfc performOneScroll:-60];
    EXPECT_EQ(height, NSHeight([[bbfc window] frame]));
    EXPECT_TRUE(NSContainsRect(screenFrame,
                               [[bbfc window] frame]));
  }
}

@interface FakedDragInfo : NSObject {
@public
  NSPoint dropLocation_;
  NSDragOperation sourceMask_;
}
@property (nonatomic, assign) NSPoint dropLocation;
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask;
@end

@implementation FakedDragInfo

@synthesize dropLocation = dropLocation_;

- (id)init {
  if ((self = [super init])) {
    dropLocation_ = NSZeroPoint;
    sourceMask_ = NSDragOperationMove;
  }
  return self;
}

// NSDraggingInfo protocol functions.

- (id)draggingPasteboard {
  return self;
}

- (id)draggingSource {
  return self;
}

- (NSDragOperation)draggingSourceOperationMask {
  return sourceMask_;
}

- (NSPoint)draggingLocation {
  return dropLocation_;
}

// Other functions.

- (void)setDraggingSourceOperationMask:(NSDragOperation)mask {
  sourceMask_ = mask;
}

@end


class BookmarkBarFolderControllerMenuTest : public CocoaTest {
 public:
  BrowserTestHelper helper_;
  scoped_nsobject<NSView> parent_view_;
  scoped_nsobject<ViewResizerPong> resizeDelegate_;
  scoped_nsobject<BookmarkBarController> bar_;

  BookmarkBarFolderControllerMenuTest() {
    resizeDelegate_.reset([[ViewResizerPong alloc] init]);
    NSRect parent_frame = NSMakeRect(0, 0, 800, 50);
    parent_view_.reset([[NSView alloc] initWithFrame:parent_frame]);
    [parent_view_ setHidden:YES];
    bar_.reset([[BookmarkBarController alloc]
                initWithBrowser:helper_.browser()
                   initialWidth:NSWidth(parent_frame)
                       delegate:nil
                 resizeDelegate:resizeDelegate_.get()]);
    InstallAndToggleBar(bar_.get());
  }

  void InstallAndToggleBar(BookmarkBarController* bar) {
    // Force loading of the nib.
    [bar view];
    // Awkwardness to look like we've been installed.
    [parent_view_ addSubview:[bar view]];
    NSRect frame = [[[bar view] superview] frame];
    frame.origin.y = 100;
    [[[bar view] superview] setFrame:frame];

    // Make sure it's on in a window so viewDidMoveToWindow is called
    [[test_window() contentView] addSubview:parent_view_];

    // Make sure it's open so certain things aren't no-ops.
    [bar updateAndShowNormalBar:YES
                showDetachedBar:NO
                  withAnimation:NO];
  }
};

TEST_F(BookmarkBarFolderControllerMenuTest, DragMoveBarBookmarkToFolder) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b "
      "2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ 4f2f1b "
      "4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu and drag in a button from the bar.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"2f"];
  NSRect oldToFolderFrame = [toFolder frame];
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSWindow* toWindow = [folderController window];
  EXPECT_TRUE(toWindow);
  NSRect oldToWindowFrame = [toWindow frame];
  // Drag a bar button onto a bookmark (i.e. not a folder) in a folder
  // so it should end up below the target bookmark.
  BookmarkButton* draggedButton = [bar_ buttonWithTitleEqualTo:@"1b"];
  ASSERT_TRUE(draggedButton);
  CGFloat horizontalShift =
      NSWidth([draggedButton frame]) + bookmarks::kBookmarkHorizontalPadding;
  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"2f1b"];
  ASSERT_TRUE(targetButton);
  [folderController dragButton:draggedButton
                            to:[targetButton center]
                          copy:NO];
  // The button should have landed just after "2f1b".
  const std::wstring expected_string(L"2f:[ 2f1b 1b 2f2f:[ 2f2f1b "
      "2f2f2b 2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ "
      "4f2f1b 4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  EXPECT_EQ(expected_string, model_test_utils::ModelStringFromNode(root));

  // Verify the window still appears by looking for its controller.
  EXPECT_TRUE([bar_ folderController]);

  // Gather the new frames.
  NSRect newToFolderFrame = [toFolder frame];
  NSRect newToWindowFrame = [toWindow frame];
  // The toFolder should have shifted left horizontally but not vertically.
  NSRect expectedToFolderFrame =
      NSOffsetRect(oldToFolderFrame, -horizontalShift, 0);
  EXPECT_NSRECT_EQ(expectedToFolderFrame, newToFolderFrame);
  // The toWindow should have shifted left horizontally, down vertically,
  // and grown vertically.
  NSRect expectedToWindowFrame = oldToWindowFrame;
  expectedToWindowFrame.origin.x -= horizontalShift;
  expectedToWindowFrame.origin.y -= bookmarks::kBookmarkBarHeight;
  expectedToWindowFrame.size.height += bookmarks::kBookmarkBarHeight;
  EXPECT_NSRECT_EQ(expectedToWindowFrame, newToWindowFrame);

  // Move the button back to the bar at the beginning.
  draggedButton = [folderController buttonWithTitleEqualTo:@"1b"];
  ASSERT_TRUE(draggedButton);
  targetButton = [bar_ buttonWithTitleEqualTo:@"2f"];
  ASSERT_TRUE(targetButton);
  [bar_ dragButton:draggedButton
                to:[targetButton left]
              copy:NO];
  EXPECT_EQ(model_string, model_test_utils::ModelStringFromNode(root));
  // Don't check the folder window since it's not supposed to be showing.
}

TEST_F(BookmarkBarFolderControllerMenuTest, DragCopyBarBookmarkToFolder) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b "
      "2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ 4f2f1b "
      "4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu and copy in a button from the bar.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"2f"];
  ASSERT_TRUE(toFolder);
  NSRect oldToFolderFrame = [toFolder frame];
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSWindow* toWindow = [folderController window];
  EXPECT_TRUE(toWindow);
  NSRect oldToWindowFrame = [toWindow frame];
  // Drag a bar button onto a bookmark (i.e. not a folder) in a folder
  // so it should end up below the target bookmark.
  BookmarkButton* draggedButton = [bar_ buttonWithTitleEqualTo:@"1b"];
  ASSERT_TRUE(draggedButton);
  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"2f1b"];
  ASSERT_TRUE(targetButton);
  [folderController dragButton:draggedButton
                            to:[targetButton center]
                          copy:YES];
  // The button should have landed just after "2f1b".
  const std::wstring expected_1(L"1b 2f:[ 2f1b 1b 2f2f:[ 2f2f1b "
    "2f2f2b 2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ "
    "4f2f1b 4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  EXPECT_EQ(expected_1, model_test_utils::ModelStringFromNode(root));

  // Gather the new frames.
  NSRect newToFolderFrame = [toFolder frame];
  NSRect newToWindowFrame = [toWindow frame];
  // The toFolder should have shifted.
  EXPECT_NSRECT_EQ(oldToFolderFrame, newToFolderFrame);
  // The toWindow should have shifted down vertically and grown vertically.
  NSRect expectedToWindowFrame = oldToWindowFrame;
  expectedToWindowFrame.origin.y -= bookmarks::kBookmarkBarHeight;
  expectedToWindowFrame.size.height += bookmarks::kBookmarkBarHeight;
  EXPECT_NSRECT_EQ(expectedToWindowFrame, newToWindowFrame);

  // Copy the button back to the bar after "3b".
  draggedButton = [folderController buttonWithTitleEqualTo:@"1b"];
  ASSERT_TRUE(draggedButton);
  targetButton = [bar_ buttonWithTitleEqualTo:@"4f"];
  ASSERT_TRUE(targetButton);
  [bar_ dragButton:draggedButton
                to:[targetButton left]
              copy:YES];
  const std::wstring expected_2(L"1b 2f:[ 2f1b 1b 2f2f:[ 2f2f1b "
      "2f2f2b 2f2f3b ] 2f3b ] 3b 1b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ "
      "4f2f1b 4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  EXPECT_EQ(expected_2, model_test_utils::ModelStringFromNode(root));
}

TEST_F(BookmarkBarFolderControllerMenuTest, DragMoveBarBookmarkToSubfolder) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b "
      "2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ 4f2f1b "
      "4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu and a subfolder menu.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"4f"];
  ASSERT_TRUE(toFolder);
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSWindow* toWindow = [folderController window];
  EXPECT_TRUE(toWindow);
  NSRect oldToWindowFrame = [toWindow frame];
  BookmarkButton* toSubfolder =
      [folderController buttonWithTitleEqualTo:@"4f2f"];
  ASSERT_TRUE(toSubfolder);
  NSRect oldToSubfolderFrame = [toSubfolder frame];
  [[toSubfolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                             withObject:toSubfolder];
  BookmarkBarFolderController* subfolderController =
      [folderController folderController];
  EXPECT_TRUE(subfolderController);
  NSWindow* toSubwindow = [subfolderController window];
  EXPECT_TRUE(toSubwindow);
  NSRect oldToSubwindowFrame = [toSubwindow frame];
  // Drag a bar button onto a bookmark (i.e. not a folder) in a folder
  // so it should end up below the target bookmark.
  BookmarkButton* draggedButton = [bar_ buttonWithTitleEqualTo:@"5b"];
  ASSERT_TRUE(draggedButton);
  BookmarkButton* targetButton =
      [subfolderController buttonWithTitleEqualTo:@"4f2f3b"];
  ASSERT_TRUE(targetButton);
  [subfolderController dragButton:draggedButton
                               to:[targetButton center]
                             copy:NO];
  // The button should have landed just after "2f".
  const std::wstring expected_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b "
      "2f2f2b 2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ "
      "4f2f1b 4f2f2b 4f2f3b 5b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] ");
  EXPECT_EQ(expected_string, model_test_utils::ModelStringFromNode(root));

  // Check the window layouts. The folder window should not have changed,
  // but the subfolder window should have shifted vertically and grown.
  NSRect newToWindowFrame = [toWindow frame];
  EXPECT_NSRECT_EQ(oldToWindowFrame, newToWindowFrame);
  NSRect newToSubwindowFrame = [toSubwindow frame];
  NSRect expectedToSubwindowFrame = oldToSubwindowFrame;
  expectedToSubwindowFrame.origin.y -= bookmarks::kBookmarkBarHeight;
  expectedToSubwindowFrame.size.height += bookmarks::kBookmarkBarHeight;
  EXPECT_NSRECT_EQ(expectedToSubwindowFrame, newToSubwindowFrame);
}

TEST_F(BookmarkBarFolderControllerMenuTest, DragMoveWithinFolder) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b "
      "2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ 4f2f1b "
      "4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"4f"];
  ASSERT_TRUE(toFolder);
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSWindow* toWindow = [folderController window];
  EXPECT_TRUE(toWindow);
  NSRect oldToWindowFrame = [toWindow frame];
  // Drag a folder button to the top within the same parent.
  BookmarkButton* draggedButton =
      [folderController buttonWithTitleEqualTo:@"4f2f"];
  ASSERT_TRUE(draggedButton);
  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"4f1f"];
  ASSERT_TRUE(targetButton);
  [folderController dragButton:draggedButton
                            to:[targetButton top]
                          copy:NO];
  // The button should have landed above "4f1f".
  const std::wstring expected_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b "
      "2f2f2b 2f2f3b ] 2f3b ] 3b 4f:[ 4f2f:[ 4f2f1b 4f2f2b 4f2f3b ] "
      "4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  EXPECT_EQ(expected_string, model_test_utils::ModelStringFromNode(root));

  // The window should not have gone away.
  EXPECT_TRUE([bar_ folderController]);

  // The folder window should not have changed.
  NSRect newToWindowFrame = [toWindow frame];
  EXPECT_NSRECT_EQ(oldToWindowFrame, newToWindowFrame);
}

TEST_F(BookmarkBarFolderControllerMenuTest, DragParentOntoChild) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b "
      "2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ 4f2f1b "
      "4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"4f"];
  ASSERT_TRUE(toFolder);
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSWindow* toWindow = [folderController window];
  EXPECT_TRUE(toWindow);
  // Drag a folder button to one of its children.
  BookmarkButton* draggedButton = [bar_ buttonWithTitleEqualTo:@"4f"];
  ASSERT_TRUE(draggedButton);
  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"4f3f"];
  ASSERT_TRUE(targetButton);
  [folderController dragButton:draggedButton
                            to:[targetButton top]
                          copy:NO];
  // The model should not have changed.
  EXPECT_EQ(model_string, model_test_utils::ModelStringFromNode(root));
}

TEST_F(BookmarkBarFolderControllerMenuTest, DragMoveChildToParent) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b "
      "2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f:[ 4f2f1b "
      "4f2f2b 4f2f3b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu and a subfolder menu.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"4f"];
  ASSERT_TRUE(toFolder);
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  BookmarkButton* toSubfolder =
      [folderController buttonWithTitleEqualTo:@"4f2f"];
  ASSERT_TRUE(toSubfolder);
  [[toSubfolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                             withObject:toSubfolder];
  BookmarkBarFolderController* subfolderController =
      [folderController folderController];
  EXPECT_TRUE(subfolderController);

  // Drag a subfolder bookmark to the parent folder.
  BookmarkButton* draggedButton =
      [subfolderController buttonWithTitleEqualTo:@"4f2f3b"];
  ASSERT_TRUE(draggedButton);
  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"4f2f"];
  ASSERT_TRUE(targetButton);
  [folderController dragButton:draggedButton
                            to:[targetButton top]
                          copy:NO];
  // The button should have landed above "4f2f".
  const std::wstring expected_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b "
      "2f2f3b ] 2f3b ] 3b 4f:[ 4f1f:[ 4f1f1b 4f1f2b 4f1f3b ] 4f2f3b 4f2f:[ "
      "4f2f1b 4f2f2b ] 4f3f:[ 4f3f1b 4f3f2b 4f3f3b ] ] 5b ");
  EXPECT_EQ(expected_string, model_test_utils::ModelStringFromNode(root));

  // The window should not have gone away.
  EXPECT_TRUE([bar_ folderController]);
  // The subfolder should have gone away.
  EXPECT_FALSE([folderController folderController]);
}

TEST_F(BookmarkBarFolderControllerMenuTest, DragWindowResizing) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring
      model_string(L"a b:[ b1 b2 b3 ] reallyReallyLongBookmarkName c ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"b"];
  ASSERT_TRUE(toFolder);
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSWindow* toWindow = [folderController window];
  EXPECT_TRUE(toWindow);
  CGFloat oldWidth = NSWidth([toWindow frame]);
  // Drag the bookmark with a long name to the folder.
  BookmarkButton* draggedButton =
      [bar_ buttonWithTitleEqualTo:@"reallyReallyLongBookmarkName"];
  ASSERT_TRUE(draggedButton);
  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"b1"];
  ASSERT_TRUE(targetButton);
  [folderController dragButton:draggedButton
                            to:[targetButton center]
                          copy:NO];
  // Verify the model change.
  const std::wstring
      expected_string(L"a b:[ b1 reallyReallyLongBookmarkName b2 b3 ] c ");
  EXPECT_EQ(expected_string, model_test_utils::ModelStringFromNode(root));
  // Verify the window grew. Just test a reasonable width gain.
  CGFloat newWidth = NSWidth([toWindow frame]);
  EXPECT_LT(oldWidth + 30.0, newWidth);
}

TEST_F(BookmarkBarFolderControllerMenuTest, MoveRemoveAddButtons) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2b 2f3b ] 3b 4b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Pop up a folder menu.
  BookmarkButton* toFolder = [bar_ buttonWithTitleEqualTo:@"2f"];
  ASSERT_TRUE(toFolder);
  [[toFolder target] performSelector:@selector(openBookmarkFolderFromButton:)
                          withObject:toFolder];
  BookmarkBarFolderController* folder = [bar_ folderController];
  EXPECT_TRUE(folder);

  // Remember how many buttons are showing.
  NSArray* buttons = [folder buttons];
  NSUInteger oldDisplayedButtons = [buttons count];

  // Move a button around a bit.
  [folder moveButtonFromIndex:0 toIndex:2];
  EXPECT_TRUE([[[buttons objectAtIndex:0] title] isEqualToString:@"2f2b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:1] title] isEqualToString:@"2f3b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:2] title] isEqualToString:@"2f1b"]);
  EXPECT_EQ(oldDisplayedButtons, [buttons count]);
  [folder moveButtonFromIndex:2 toIndex:0];
  EXPECT_TRUE([[[buttons objectAtIndex:0] title] isEqualToString:@"2f1b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:1] title] isEqualToString:@"2f2b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:2] title] isEqualToString:@"2f3b"]);
  EXPECT_EQ(oldDisplayedButtons, [buttons count]);

  // Add a couple of buttons.
  const BookmarkNode* node = root->GetChild(2); // Purloin an existing node.
  [folder addButtonForNode:node atIndex:0];
  EXPECT_TRUE([[[buttons objectAtIndex:0] title] isEqualToString:@"3b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:1] title] isEqualToString:@"2f1b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:2] title] isEqualToString:@"2f2b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:3] title] isEqualToString:@"2f3b"]);
  EXPECT_EQ(oldDisplayedButtons + 1, [buttons count]);
  node = root->GetChild(3);
  [folder addButtonForNode:node atIndex:-1];
  EXPECT_TRUE([[[buttons objectAtIndex:0] title] isEqualToString:@"3b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:1] title] isEqualToString:@"2f1b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:2] title] isEqualToString:@"2f2b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:3] title] isEqualToString:@"2f3b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:4] title] isEqualToString:@"4b"]);
  EXPECT_EQ(oldDisplayedButtons + 2, [buttons count]);

  // Remove a couple of buttons.
  [folder removeButton:4 animate:NO];
  [folder removeButton:1 animate:NO];
  EXPECT_TRUE([[[buttons objectAtIndex:0] title] isEqualToString:@"3b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:1] title] isEqualToString:@"2f2b"]);
  EXPECT_TRUE([[[buttons objectAtIndex:2] title] isEqualToString:@"2f3b"]);
  EXPECT_EQ(oldDisplayedButtons, [buttons count]);
}

TEST_F(BookmarkBarFolderControllerMenuTest, ControllerForNode) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2b ] 3b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Find the main bar controller.
  const void* expectedController = bar_;
  const void* actualController = [bar_ controllerForNode:root];
  EXPECT_EQ(expectedController, actualController);

  // Pop up the folder menu.
  BookmarkButton* targetFolder = [bar_ buttonWithTitleEqualTo:@"2f"];
  ASSERT_TRUE(targetFolder);
  [[targetFolder target]
   performSelector:@selector(openBookmarkFolderFromButton:)
   withObject:targetFolder];
  BookmarkBarFolderController* folder = [bar_ folderController];
  EXPECT_TRUE(folder);

  // Find the folder controller using the folder controller.
  const BookmarkNode* targetNode = root->GetChild(1);
  expectedController = folder;
  actualController = [bar_ controllerForNode:targetNode];
  EXPECT_EQ(expectedController, actualController);

  // Find the folder controller from the bar.
  actualController = [folder controllerForNode:targetNode];
  EXPECT_EQ(expectedController, actualController);
}

TEST_F(BookmarkBarFolderControllerMenuTest, MenuSizingAndScrollArrows) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2b 3b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  const BookmarkNode* parent = model.GetBookmarkBarNode();
  const BookmarkNode* folder = model.AddGroup(parent,
                                              parent->GetChildCount(),
                                              L"BIG");

  // Pop open the new folder window and verify it has one (empty) item.
  BookmarkButton* button = [bar_ buttonWithTitleEqualTo:@"BIG"];
  [[button target] performSelector:@selector(openBookmarkFolderFromButton:)
                        withObject:button];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSWindow* folderMenu = [folderController window];
  EXPECT_TRUE(folderMenu);
  CGFloat expectedHeight = (CGFloat)bookmarks::kBookmarkButtonHeight;
  NSRect menuFrame = [folderMenu frame];
  CGFloat menuHeight = NSHeight(menuFrame);
  EXPECT_CGFLOAT_EQ(expectedHeight, menuHeight);
  EXPECT_FALSE([folderController scrollable]);

  // Now add a real bookmark and reopen.
  model.AddURL(folder, folder->GetChildCount(), L"a", GURL("http://a.com/"));
  folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  folderMenu = [folderController window];
  EXPECT_TRUE(folderMenu);
  menuFrame = [folderMenu frame];
  menuHeight = NSHeight(menuFrame);
  EXPECT_CGFLOAT_EQ(expectedHeight, menuHeight);
  CGFloat menuWidth = NSWidth(menuFrame);
  button = [folderController buttonWithTitleEqualTo:@"a"];
  CGFloat buttonWidth = NSWidth([button frame]);
  CGFloat expectedWidth =
      buttonWidth + (2 * bookmarks::kBookmarkVerticalPadding) +
      bookmarks::kScrollViewContentWidthMargin;
  EXPECT_CGFLOAT_EQ(expectedWidth, menuWidth);

  // Add a wider bookmark and make sure the button widths match.
  model.AddURL(folder, folder->GetChildCount(), L"A really, really long name",
               GURL("http://www.google.com/a"));
  EXPECT_LT(menuWidth, NSWidth([folderMenu frame]));
  EXPECT_LT(buttonWidth, NSWidth([button frame]));
  buttonWidth = NSWidth([button frame]);
  BookmarkButton* buttonB =
      [folderController buttonWithTitleEqualTo:@"A really, really long name"];
  EXPECT_TRUE(buttonB);
  CGFloat buttonWidthB = NSWidth([buttonB frame]);
  EXPECT_CGFLOAT_EQ(buttonWidth, buttonWidthB);
  // Add a bunch of bookmarks until the window grows no more, then check for
  // a scroll down arrow.
  CGFloat oldMenuHeight = 0.0;  // It just has to be different for first run.
  menuHeight = NSHeight([folderMenu frame]);
  NSUInteger tripWire = 0;  // Prevent a runaway.
  while (![folderController scrollable] && ++tripWire < 100) {
    model.AddURL(folder, folder->GetChildCount(), L"B", GURL("http://b.com/"));
    oldMenuHeight = menuHeight;
    menuHeight = NSHeight([folderMenu frame]);
  }
  EXPECT_TRUE([folderController scrollable]);
  EXPECT_TRUE([folderController canScrollUp]);

  // Remove one bookmark and make sure the scroll down arrow has been removed.
  // We'll remove the really long node so we can see if the buttons get resized.
  menuWidth = NSWidth([folderMenu frame]);
  buttonWidth = NSWidth([button frame]);
  model.Remove(folder, 1);
  EXPECT_FALSE([folderController scrollable]);
  EXPECT_FALSE([folderController canScrollUp]);
  EXPECT_FALSE([folderController canScrollDown]);

  // Check the size. It should have reduced.
  EXPECT_GT(menuWidth, NSWidth([folderMenu frame]));
  EXPECT_GT(buttonWidth, NSWidth([button frame]));
}

// Just like a BookmarkBarFolderController but intercedes when providing
// pasteboard drag data.
@interface BookmarkBarFolderControllerDragData : BookmarkBarFolderController {
  const BookmarkNode* dragDataNode_;  // Weak
}
- (void)setDragDataNode:(const BookmarkNode*)node;
@end

@implementation BookmarkBarFolderControllerDragData

- (id)initWithParentButton:(BookmarkButton*)button
          parentController:(BookmarkBarFolderController*)parentController
             barController:(BookmarkBarController*)barController {
  if ((self = [super initWithParentButton:button
                         parentController:parentController
                            barController:barController])) {
    dragDataNode_ = NULL;
  }
  return self;
}

- (void)setDragDataNode:(const BookmarkNode*)node {
  dragDataNode_ = node;
}

- (std::vector<const BookmarkNode*>)retrieveBookmarkDragDataNodes {
  std::vector<const BookmarkNode*> dragDataNodes;
  if(dragDataNode_) {
    dragDataNodes.push_back(dragDataNode_);
  }
  return dragDataNodes;
}

@end

TEST_F(BookmarkBarFolderControllerMenuTest, DragBookmarkData) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b 2f2f3b ] "
                                  "2f3b ] 3b 4b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);
  const BookmarkNode* other = model.other_node();
  const std::wstring other_string(L"O1b O2b O3f:[ O3f1b O3f2f ] "
                                  "O4f:[ O4f1b O4f2f ] 05b ");
  model_test_utils::AddNodesFromModelString(model, other, other_string);

  // Validate initial model.
  std::wstring actual = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actual);
  actual = model_test_utils::ModelStringFromNode(other);
  EXPECT_EQ(other_string, actual);

  // Pop open a folder.
  BookmarkButton* button = [bar_ buttonWithTitleEqualTo:@"2f"];
  scoped_nsobject<BookmarkBarFolderControllerDragData> folderController;
  folderController.reset([[BookmarkBarFolderControllerDragData alloc]
                          initWithParentButton:button
                              parentController:nil
                                 barController:bar_]);
  [folderController window];
  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"2f1b"];
  ASSERT_TRUE(targetButton);

  // Gen up some dragging data.
  const BookmarkNode* newNode = other->GetChild(2);
  [folderController setDragDataNode:newNode];
  scoped_nsobject<FakedDragInfo> dragInfo([[FakedDragInfo alloc] init]);
  [dragInfo setDropLocation:[targetButton top]];
  [folderController dragBookmarkData:(id<NSDraggingInfo>)dragInfo.get()];

  // Verify the model.
  const std::wstring expected(L"1b 2f:[ O3f:[ O3f1b O3f2f ] 2f1b 2f2f:[ 2f2f1b "
                              "2f2f2b 2f2f3b ] 2f3b ] 3b 4b ");
  actual = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(expected, actual);

  // Now drag over a folder button.
  targetButton = [folderController buttonWithTitleEqualTo:@"2f2f"];
  ASSERT_TRUE(targetButton);
  newNode = other->GetChild(2);  // Should be O4f.
  EXPECT_EQ(newNode->GetTitle(), L"O4f");
  [folderController setDragDataNode:newNode];
  [dragInfo setDropLocation:[targetButton center]];
  [folderController dragBookmarkData:(id<NSDraggingInfo>)dragInfo.get()];

  // Verify the model.
  const std::wstring expectedA(L"1b 2f:[ O3f:[ O3f1b O3f2f ] 2f1b 2f2f:[ "
                               "2f2f1b 2f2f2b 2f2f3b O4f:[ O4f1b O4f2f ] ] "
                               "2f3b ] 3b 4b ");
  actual = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(expectedA, actual);
}

TEST_F(BookmarkBarFolderControllerMenuTest, AddURLs) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b 2f2f3b ] "
                                  "2f3b ] 3b 4b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actual = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actual);

  // Pop open a folder.
  BookmarkButton* button = [bar_ buttonWithTitleEqualTo:@"2f"];
  [[button target] performSelector:@selector(openBookmarkFolderFromButton:)
                        withObject:button];
  BookmarkBarFolderController* folderController = [bar_ folderController];
  EXPECT_TRUE(folderController);
  NSArray* buttons = [folderController buttons];
  EXPECT_TRUE(buttons);

  // Remember how many buttons are showing.
  int oldDisplayedButtons = [buttons count];

  BookmarkButton* targetButton =
      [folderController buttonWithTitleEqualTo:@"2f1b"];
  ASSERT_TRUE(targetButton);

  NSArray* urls = [NSArray arrayWithObjects: @"http://www.a.com/",
                   @"http://www.b.com/", nil];
  NSArray* titles = [NSArray arrayWithObjects: @"SiteA", @"SiteB", nil];
  [folderController addURLs:urls withTitles:titles at:[targetButton top]];

  // There should two more buttons in the folder.
  int newDisplayedButtons = [buttons count];
  EXPECT_EQ(oldDisplayedButtons + 2, newDisplayedButtons);
  // Verify the model.
  const std::wstring expected(L"1b 2f:[ SiteA SiteB 2f1b 2f2f:[ 2f2f1b 2f2f2b "
                              "2f2f3b ] 2f3b ] 3b 4b ");
  actual = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(expected, actual);
}

TEST_F(BookmarkBarFolderControllerMenuTest, DropPositionIndicator) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b 2f2f3b ] "
                                  "2f3b ] 3b 4b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actual = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actual);

  // Pop open the folder.
  BookmarkButton* button = [bar_ buttonWithTitleEqualTo:@"2f"];
  [[button target] performSelector:@selector(openBookmarkFolderFromButton:)
                        withObject:button];
  BookmarkBarFolderController* folder = [bar_ folderController];
  EXPECT_TRUE(folder);

  // Test a series of points starting at the top of the folder.
  const CGFloat yOffset = 0.5 * bookmarks::kBookmarkVerticalPadding;
  BookmarkButton* targetButton = [folder buttonWithTitleEqualTo:@"2f1b"];
  ASSERT_TRUE(targetButton);
  NSPoint targetPoint = [targetButton top];
  CGFloat pos = [folder indicatorPosForDragToPoint:targetPoint];
  EXPECT_CGFLOAT_EQ(targetPoint.y + yOffset, pos);
  pos = [folder indicatorPosForDragToPoint:[targetButton bottom]];
  targetButton = [folder buttonWithTitleEqualTo:@"2f2f"];
  EXPECT_CGFLOAT_EQ([targetButton top].y + yOffset, pos);
  pos = [folder indicatorPosForDragToPoint:NSMakePoint(10,0)];
  targetButton = [folder buttonWithTitleEqualTo:@"2f3b"];
  EXPECT_CGFLOAT_EQ([targetButton bottom].y - yOffset, pos);
}

@interface BookmarkBarControllerNoDelete : BookmarkBarController
- (IBAction)deleteBookmark:(id)sender;
@end

@implementation BookmarkBarControllerNoDelete
- (IBAction)deleteBookmark:(id)sender {
  // NOP
}
@end

class BookmarkBarFolderControllerClosingTest : public
    BookmarkBarFolderControllerMenuTest {
 public:
  BookmarkBarFolderControllerClosingTest() {
    bar_.reset([[BookmarkBarControllerNoDelete alloc]
                initWithBrowser:helper_.browser()
                   initialWidth:NSWidth([parent_view_ frame])
                       delegate:nil
                 resizeDelegate:resizeDelegate_.get()]);
    InstallAndToggleBar(bar_.get());
  }
};

TEST_F(BookmarkBarFolderControllerClosingTest, DeleteClosesFolder) {
  BookmarkModel& model(*helper_.profile()->GetBookmarkModel());
  const BookmarkNode* root = model.GetBookmarkBarNode();
  const std::wstring model_string(L"1b 2f:[ 2f1b 2f2f:[ 2f2f1b 2f2f2b ] "
                                   "2f3b ] 3b ");
  model_test_utils::AddNodesFromModelString(model, root, model_string);

  // Validate initial model.
  std::wstring actualModelString = model_test_utils::ModelStringFromNode(root);
  EXPECT_EQ(model_string, actualModelString);

  // Open the folder menu and submenu.
  BookmarkButton* target = [bar_ buttonWithTitleEqualTo:@"2f"];
  ASSERT_TRUE(target);
  [[target target] performSelector:@selector(openBookmarkFolderFromButton:)
                              withObject:target];
  BookmarkBarFolderController* folder = [bar_ folderController];
  EXPECT_TRUE(folder);
  BookmarkButton* subTarget = [folder buttonWithTitleEqualTo:@"2f2f"];
  ASSERT_TRUE(subTarget);
  [[subTarget target] performSelector:@selector(openBookmarkFolderFromButton:)
                           withObject:subTarget];
  BookmarkBarFolderController* subFolder = [folder folderController];
  EXPECT_TRUE(subFolder);

  // Delete the folder node and verify the window closed down by looking
  // for its controller again.
  [folder deleteBookmark:folder];
  EXPECT_FALSE([folder folderController]);
}

// TODO(jrg): draggingEntered: and draggingExited: trigger timers so
// they are hard to test.  Factor out "fire timers" into routines
// which can be overridden to fire immediately to make behavior
// confirmable.
// There is a similar problem with mouseEnteredButton: and
// mouseExitedButton:.
