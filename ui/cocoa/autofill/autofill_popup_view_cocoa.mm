// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "chrome/browser/ui/cocoa/autofill/autofill_popup_view_cocoa.h"

#include "base/i18n/rtl.h"
#include "base/logging.h"
#include "base/sys_string_conversions.h"
#include "chrome/browser/ui/autofill/autofill_popup_controller.h"
#include "chrome/browser/ui/cocoa/autofill/autofill_popup_view_bridge.h"
#include "grit/ui_resources.h"
#include "third_party/WebKit/Source/WebKit/chromium/public/WebAutofillClient.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/point.h"
#include "ui/gfx/rect.h"

namespace {

NSColor* BorderColor() {
  // TODO(isherman): This color does not match the other platforms, but it
  // matches what the existing UI on Mac has as the color.  The other platforms
  // have a strange color: the RGB values are almost, but not quite, identical
  // to each other.
  // TODO(isherman): Maybe use a system color for this?
  return [NSColor colorWithCalibratedRed:127 / 255.0
                                   green:157 / 255.0
                                    blue:185 / 255.0
                                   alpha:1.0];
}

NSColor* SeparatorColor() {
  return [NSColor colorWithCalibratedWhite:220 / 255.0 alpha:1];
}

NSColor* HighlightColor() {
  return [NSColor colorWithCalibratedWhite:205 / 255.0 alpha:1];
}

}  // anonymous namespace

#pragma mark -
#pragma mark Private methods

@interface AutofillPopupViewCocoa ()

// Draws a thin separator in the popup UI.
- (void)drawSeparatorWithBounds:(NSRect)bounds;

// Draws an Autofill suggestion in the given |bounds|, labeled with the given
// |name| and |subtext| hint.  If the suggestion |isSelected|, then it is drawn
// with a highlight.  Some suggestions -- such as for credit cards -- might also
// include an |icon| -- e.g. for the card type.  Finally, if |canDelete| is
// true, a delete icon is also drawn.
- (void)drawSuggestionWithName:(NSString*)name
                       subtext:(NSString*)subtext
                          icon:(NSImage*)icon
                        bounds:(NSRect)bounds
                      selected:(BOOL)isSelected
                     canDelete:(BOOL)canDelete;

// Returns the icon for the row with the given |index|, or |nil| if there is
// none.
- (NSImage*)iconAtIndex:(size_t)index;

@end

@implementation AutofillPopupViewCocoa

#pragma mark -
#pragma mark Initialisers

- (id)initWithFrame:(NSRect)frame {
  NOTREACHED();
  return [self initWithController:NULL frame:frame];
}

- (id)initWithController:(AutofillPopupController*)controller
                   frame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self)
    controller_ = controller;

  return self;
}

#pragma mark -
#pragma mark NSView implementation:

// A slight optimization for drawing:
// https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/CocoaViewsGuide/Optimizing/Optimizing.html
- (BOOL)isOpaque {
  return YES;
}

- (BOOL)isFlipped {
  // Flipped so that it's easier to share controller logic with other OSes.
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  // If the view is in the process of being destroyed, don't bother drawing.
  if (!controller_)
    return;

  // TODO(isherman): Is there a better way to leave room for the border?
  // TODO(isherman): Drawing the border as part of the content view means that
  // the rest of the content has to be careful not to overlap the border.
  // Should the border be part of the window instead?  If not, should the rest
  // of the view be a subview?  Or should I just draw the window content
  // carefully?
  // TODO(isherman): We should consider using asset-based drawing for the
  // border, creating simple bitmaps for the view's border and background, and
  // drawing them using NSDrawNinePartImage().
  NSRect borderRect = NSInsetRect([self bounds], 0.5, 0.5);
  NSBezierPath* border = [NSBezierPath bezierPathWithRect:borderRect];

  [[NSColor whiteColor] set];
  [border fill];

  // TODO(isherman): This color does not match the other platforms, but it
  // matches what the existing UI on Mac has as the color.  The other platforms
  // have a strange color: the RGB values are almost, but not quite, identical
  // to each other.
  // TODO(isherman): Maybe use a system color for this?
  [BorderColor() set];
  [border stroke];

  for (size_t i = 0; i < controller_->names().size(); ++i) {
    // Skip rows outside of the dirty rect.
    NSRect rowBounds =
        NSRectFromCGRect(controller_->GetRowBounds(i).ToCGRect());
    if (!NSIntersectsRect(rowBounds, dirtyRect))
      continue;

    if (controller_->identifiers()[i] ==
            WebKit::WebAutofillClient::MenuItemIDSeparator) {
      [self drawSeparatorWithBounds:rowBounds];
    } else {
      NSString* name = SysUTF16ToNSString(controller_->names()[i]);
      NSString* subtext = SysUTF16ToNSString(controller_->subtexts()[i]);
      BOOL isSelected = static_cast<int>(i) == controller_->selected_line();
      [self drawSuggestionWithName:name
                           subtext:subtext
                              icon:[self iconAtIndex:i]
                            bounds:rowBounds
                          selected:isSelected
                         canDelete:controller_->CanDelete(i)];
    }
  }
}

- (void)mouseUp:(NSEvent*)theEvent {
  // If the view is in the process of being destroyed, abort.
  if (!controller_)
    return;

  NSPoint location = [self convertPoint:[theEvent locationInWindow]
                               fromView:nil];

  if (NSPointInRect(location, [self bounds])) {
    controller_->MouseClicked(static_cast<int>(location.x),
                              static_cast<int>(location.y));
  }
}

- (void)mouseMoved:(NSEvent*)theEvent {
  // If the view is in the process of being destroyed, abort.
  if (!controller_)
    return;

  NSPoint location = [self convertPoint:[theEvent locationInWindow]
                               fromView:nil];

  controller_->MouseHovered(static_cast<int>(location.x),
                            static_cast<int>(location.y));
}

- (void)mouseDragged:(NSEvent*)theEvent {
  [self mouseMoved:theEvent];
}

- (void)mouseExited:(NSEvent*)theEvent {
  // If the view is in the process of being destroyed, abort.
  if (!controller_)
    return;

  controller_->MouseExitedPopup();
}

#pragma mark -
#pragma mark Public API:

- (void)controllerDestroyed {
  // Since the |controller_| either already has been destroyed or is about to
  // be, about the only thing we can safely do with it is to null it out.
  controller_ = NULL;
}

#pragma mark -
#pragma mark Private API:

- (void)drawSeparatorWithBounds:(NSRect)bounds {
  [SeparatorColor() set];
  [NSBezierPath fillRect:bounds];
}

- (void)drawSuggestionWithName:(NSString*)name
                       subtext:(NSString*)subtext
                          icon:(NSImage*)icon
                        bounds:(NSRect)bounds
                      selected:(BOOL)isSelected
                     canDelete:(BOOL)canDelete {
  // If this row is selected, highlight it.
  if (isSelected) {
    // TODO(isherman): The highlight color should match the system highlight
    // color.  Maybe use controlHighlightColor or selectedTextBackgroundColor
    // for this?
    [HighlightColor() set];
    [NSBezierPath fillRect:bounds];
  }

  BOOL isRTL = base::i18n::IsRTL();

  // TODO(isherman): Set font, colors, and any other appropriate attributes.
  NSSize nameSize = [name sizeWithAttributes:nil];
  CGFloat x = bounds.origin.x +
      (isRTL ?
       bounds.size.width - AutofillPopupView::kEndPadding - nameSize.width:
       AutofillPopupView::kEndPadding);
  CGFloat y = bounds.origin.y + (bounds.size.height - nameSize.height) / 2;

  [name drawAtPoint:NSMakePoint(x, y) withAttributes:nil];

  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();

  // The x-coordinate will be updated as each element is drawn.
  x = bounds.origin.x +
      (isRTL ?
       AutofillPopupView::kEndPadding :
       bounds.size.width - AutofillPopupView::kEndPadding);

  // Draw the delete icon, if one is needed.
  if (canDelete) {
    // TODO(isherman): Refactor the cross-platform code so that the delete icon
    // is a button implemented as a subview, rather than having all its logic be
    // custom handled by the controller.
    // TODO(csharp): Create a custom resource for the delete icon.
    // http://crbug.com/131801
    NSImage* deleteIcon;
    if (isSelected && controller_->delete_icon_hovered())
      deleteIcon = rb.GetNativeImageNamed(IDR_CLOSE_BAR_H).ToNSImage();
    else
      deleteIcon = rb.GetNativeImageNamed(IDR_CLOSE_BAR).ToNSImage();

    NSSize iconSize = [deleteIcon size];
    x += isRTL ? 0 : -iconSize.width;
    y = bounds.origin.y + (bounds.size.height - iconSize.height) / 2;
    [deleteIcon drawInRect:NSMakeRect(x, y, iconSize.width, iconSize.height)
                  fromRect:NSZeroRect
                 operation:NSCompositeSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:nil];

    x += isRTL ?
        iconSize.width + AutofillPopupView::kIconPadding :
        -AutofillPopupView::kIconPadding;
  }

  // Draw the Autofill icon, if one exists.
  if (icon) {
    NSSize iconSize = [icon size];
    x += isRTL ? 0 : -iconSize.width;
    y = bounds.origin.y + (bounds.size.height - iconSize.height) / 2;
    [icon drawInRect:NSMakeRect(x, y, iconSize.width, iconSize.height)
            fromRect:NSZeroRect
           operation:NSCompositeSourceOver
            fraction:1.0
      respectFlipped:YES
               hints:nil];

    x += isRTL ?
        iconSize.width + AutofillPopupView::kIconPadding :
        -AutofillPopupView::kIconPadding;
  }

  // Draw the subtext.
  NSSize subtextSize = [subtext sizeWithAttributes:nil];
  x += isRTL ? 0 : -subtextSize.width;
  y = bounds.origin.y + (bounds.size.height - subtextSize.height) / 2;

  [subtext drawAtPoint:NSMakePoint(x, y) withAttributes:nil];
}

- (NSImage*)iconAtIndex:(size_t)index {
  if (controller_->icons()[index].empty())
    return nil;

  int iconId = controller_->GetIconResourceID(controller_->icons()[index]);
  DCHECK_NE(-1, iconId);

  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  return rb.GetNativeImageNamed(iconId).ToNSImage();
}

@end