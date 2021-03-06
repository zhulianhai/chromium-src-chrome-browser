// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/ui/views/autofill/autofill_dialog_views.h"

#include <utility>

#include "base/utf_string_conversions.h"
#include "chrome/browser/ui/autofill/autofill_dialog_controller.h"
#include "chrome/browser/ui/views/constrained_window_views.h"
#include "grit/theme_resources.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/canvas.h"
#include "ui/views/background.h"
#include "ui/views/border.h"
#include "ui/views/controls/button/checkbox.h"
#include "ui/views/controls/button/image_button.h"
#include "ui/views/controls/combobox/combobox.h"
#include "ui/views/controls/label.h"
#include "ui/views/controls/menu/menu_model_adapter.h"
#include "ui/views/controls/menu/menu_runner.h"
#include "ui/views/controls/separator.h"
#include "ui/views/controls/textfield/textfield.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/layout/fill_layout.h"
#include "ui/views/layout/grid_layout.h"
#include "ui/views/layout/layout_constants.h"

namespace autofill {

namespace {

// Size of the triangular mark that indicates an invalid textfield.
const int kDogEarSize = 10;

const char kDecoratedTextfieldClassName[] = "autofill/DecoratedTextfield";

// Returns a label that describes a details section.
views::Label* CreateDetailsSectionLabel(const string16& text) {
  views::Label* label = new views::Label(text);
  label->SetHorizontalAlignment(gfx::ALIGN_RIGHT);
  label->SetFont(label->font().DeriveFont(0, gfx::Font::BOLD));
  // TODO(estade): this should be made to match the native textfield top
  // inset. It's hard to get at, so for now it's hard-coded.
  label->set_border(views::Border::CreateEmptyBorder(4, 0, 0, 0));
  return label;
}

}  // namespace

// AutofillDialogViews::DecoratedTextfield -------------------------------------

AutofillDialogViews::DecoratedTextfield::DecoratedTextfield(
    const string16& default_value,
    const string16& placeholder,
    views::TextfieldController* controller)
    : textfield_(new views::Textfield()),
      invalid_(false) {
  textfield_->set_placeholder_text(placeholder);
  textfield_->SetText(default_value);
  textfield_->SetController(controller);
  SetLayoutManager(new views::FillLayout());
  AddChildView(textfield_);
}

AutofillDialogViews::DecoratedTextfield::~DecoratedTextfield() {}

void AutofillDialogViews::DecoratedTextfield::SetInvalid(bool invalid) {
  invalid_ = invalid;
  if (invalid)
    textfield_->SetBorderColor(SK_ColorRED);
  else
    textfield_->UseDefaultBorderColor();
  SchedulePaint();
}

std::string AutofillDialogViews::DecoratedTextfield::GetClassName() const {
  return kDecoratedTextfieldClassName;
}

void AutofillDialogViews::DecoratedTextfield::PaintChildren(
    gfx::Canvas* canvas) {}

void AutofillDialogViews::DecoratedTextfield::OnPaint(gfx::Canvas* canvas) {
  // Draw the textfield first.
  canvas->Save();
  if (FlipCanvasOnPaintForRTLUI()) {
    canvas->Translate(gfx::Vector2d(width(), 0));
    canvas->Scale(-1, 1);
  }
  views::View::PaintChildren(canvas);
  canvas->Restore();

  // Then draw extra stuff on top.
  if (invalid_) {
    SkPath dog_ear;
    dog_ear.moveTo(width() - kDogEarSize, 0);
    dog_ear.lineTo(width(), 0);
    dog_ear.lineTo(width(), kDogEarSize);
    dog_ear.close();
    canvas->ClipPath(dog_ear);
    canvas->DrawColor(SK_ColorRED);
  }
}

// AutofillDialogViews::SectionContainer ---------------------------------------

AutofillDialogViews::SectionContainer::SectionContainer(
    const string16& label,
    views::View* controls,
    views::Button* proxy_button)
    : proxy_button_(proxy_button),
      forward_mouse_events_(false) {
  set_notify_enter_exit_on_child(true);

  views::GridLayout* layout = new views::GridLayout(this);
  SetLayoutManager(layout);

  const int kColumnSetId = 0;
  views::ColumnSet* column_set = layout->AddColumnSet(kColumnSetId);
  // TODO(estade): pull out these constants, and figure out better values
  // for them.
  column_set->AddColumn(views::GridLayout::FILL,
                        views::GridLayout::LEADING,
                        0,
                        views::GridLayout::FIXED,
                        180,
                        0);
  column_set->AddPaddingColumn(0, 15);
  column_set->AddColumn(views::GridLayout::FILL,
                        views::GridLayout::LEADING,
                        0,
                        views::GridLayout::FIXED,
                        300,
                        0);

  layout->StartRow(0, kColumnSetId);
  layout->AddView(CreateDetailsSectionLabel(label));
  layout->AddView(controls);
}

AutofillDialogViews::SectionContainer::~SectionContainer() {}

void AutofillDialogViews::SectionContainer::SetForwardMouseEvents(
    bool forward) {
  forward_mouse_events_ = forward;
  if (!forward)
    set_background(NULL);
}

void AutofillDialogViews::SectionContainer::OnMouseEntered(
    const ui::MouseEvent& event) {
  if (!forward_mouse_events_)
    return;

  // TODO(estade): use the correct color.
  set_background(views::Background::CreateSolidBackground(SK_ColorLTGRAY));
  proxy_button_->OnMouseEntered(ProxyEvent(event));
  SchedulePaint();
}

void AutofillDialogViews::SectionContainer::OnMouseExited(
    const ui::MouseEvent& event) {
  if (!forward_mouse_events_)
    return;

  set_background(NULL);
  proxy_button_->OnMouseExited(ProxyEvent(event));
  SchedulePaint();
}

bool AutofillDialogViews::SectionContainer::OnMousePressed(
    const ui::MouseEvent& event) {
  if (!forward_mouse_events_)
    return false;

  return proxy_button_->OnMousePressed(ProxyEvent(event));
}

void AutofillDialogViews::SectionContainer::OnMouseReleased(
    const ui::MouseEvent& event) {
  if (!forward_mouse_events_)
    return;

  proxy_button_->OnMouseReleased(ProxyEvent(event));
}

// static
ui::MouseEvent AutofillDialogViews::SectionContainer::ProxyEvent(
    const ui::MouseEvent& event) {
  ui::MouseEvent event_copy = event;
  event_copy.set_location(gfx::Point());
  return event_copy;
}

// AutofillDialogView ----------------------------------------------------------

// static
AutofillDialogView* AutofillDialogView::Create(
    AutofillDialogController* controller) {
  return new AutofillDialogViews(controller);
}

// AutofillDialogViews ---------------------------------------------------------

AutofillDialogViews::AutofillDialogViews(AutofillDialogController* controller)
    : controller_(controller),
      did_submit_(false),
      window_(NULL),
      contents_(NULL),
      notification_label_(NULL) {
  DCHECK(controller);
  detail_groups_.insert(std::make_pair(SECTION_EMAIL,
                                       DetailsGroup(SECTION_EMAIL)));
  detail_groups_.insert(std::make_pair(SECTION_CC,
                                       DetailsGroup(SECTION_CC)));
  detail_groups_.insert(std::make_pair(SECTION_BILLING,
                                       DetailsGroup(SECTION_BILLING)));
  detail_groups_.insert(std::make_pair(SECTION_SHIPPING,
                                       DetailsGroup(SECTION_SHIPPING)));
}

AutofillDialogViews::~AutofillDialogViews() {
  DCHECK(!window_);
}

void AutofillDialogViews::Show() {
  InitChildViews();
  UpdateNotificationArea();

  // Ownership of |contents_| is handed off by this call. The
  // WebContentsModalDialog will take care of deleting itself after calling
  // DeleteDelegate().
  window_ = new ConstrainedWindowViews(controller_->web_contents(), this);
  window_->GetFocusManager()->AddFocusChangeListener(this);
}

void AutofillDialogViews::UpdateSection(DialogSection section) {
  const DetailInputs& updated_inputs =
      controller_->RequestedFieldsForSection(section);
  DetailsGroup* group = GroupForSection(section);

  for (DetailInputs::const_iterator iter = updated_inputs.begin();
       iter != updated_inputs.end(); ++iter) {
    TextfieldMap::iterator input = group->textfields.find(&(*iter));
    if (input == group->textfields.end())
      continue;

    input->second->textfield()->SetText(iter->autofilled_value);
  }

  UpdateDetailsGroupState(*group);
}

void AutofillDialogViews::GetUserInput(DialogSection section,
                                       DetailOutputMap* output) {
  DetailsGroup* group = GroupForSection(section);
  for (TextfieldMap::iterator it = group->textfields.begin();
       it != group->textfields.end(); ++it) {
    output->insert(std::make_pair(it->first, it->second->textfield()->text()));
  }
}

bool AutofillDialogViews::UseBillingForShipping() {
  return use_billing_for_shipping_->checked();
}

string16 AutofillDialogViews::GetWindowTitle() const {
  return controller_->DialogTitle();
}

void AutofillDialogViews::WindowClosing() {
  window_->GetFocusManager()->RemoveFocusChangeListener(this);
}

void AutofillDialogViews::DeleteDelegate() {
  window_ = NULL;
  // |this| belongs to |controller_|.
  controller_->ViewClosed(did_submit_ ? ACTION_SUBMIT : ACTION_ABORT);
}

views::Widget* AutofillDialogViews::GetWidget() {
  return contents_->GetWidget();
}

const views::Widget* AutofillDialogViews::GetWidget() const {
  return contents_->GetWidget();
}

views::View* AutofillDialogViews::GetContentsView() {
  return contents_;
}

string16 AutofillDialogViews::GetDialogButtonLabel(ui::DialogButton button)
    const {
  return button == ui::DIALOG_BUTTON_OK ?
      controller_->ConfirmButtonText() : controller_->CancelButtonText();
}

bool AutofillDialogViews::IsDialogButtonEnabled(ui::DialogButton button) const {
  return button == ui::DIALOG_BUTTON_OK ?
      controller_->ConfirmButtonEnabled() : true;
}

bool AutofillDialogViews::Cancel() {
  return true;
}

bool AutofillDialogViews::Accept() {
  if (!ValidateForm())
    return false;

  did_submit_ = true;
  return true;
}

void AutofillDialogViews::ButtonPressed(views::Button* sender,
                                        const ui::Event& event) {
  if (sender == use_billing_for_shipping_) {
    UpdateDetailsGroupState(*GroupForSection(SECTION_SHIPPING));
  } else {
    // TODO(estade): Should the menu be shown on mouse down?
    DetailsGroup* group = NULL;
    for (DetailGroupMap::iterator iter = detail_groups_.begin();
         iter != detail_groups_.end(); ++iter) {
      if (sender == iter->second.suggested_button) {
        group = &iter->second;
        break;
      }
    }
    DCHECK(group);

    views::MenuModelAdapter adapter(
        controller_->MenuModelForSection(group->section));
    menu_runner_.reset(new views::MenuRunner(adapter.CreateMenu()));

    // Ignore the result since we don't need to handle a deleted menu specially.
    ignore_result(
        menu_runner_->RunMenuAt(sender->GetWidget(),
                                NULL,
                                group->suggested_button->GetBoundsInScreen(),
                                views::MenuItemView::TOPRIGHT,
                                0));
  }
}

void AutofillDialogViews::ContentsChanged(views::Textfield* sender,
                                          const string16& new_contents) {
  views::View* ancestor =
      sender->GetAncestorWithClassName(kDecoratedTextfieldClassName);
  DetailsGroup* group = NULL;
  for (DetailGroupMap::iterator iter = detail_groups_.begin();
       iter != detail_groups_.end(); ++iter) {
    if (ancestor->parent() == iter->second.manual_input) {
      group = &iter->second;
      break;
    }
  }
  DCHECK(group);

  for (TextfieldMap::const_iterator iter = group->textfields.begin();
       iter != group->textfields.end();
       ++iter) {
    DecoratedTextfield* decorated = iter->second;
    if (decorated == ancestor) {
      controller_->UserEditedInput(iter->first,
                                   group->section,
                                   GetWidget()->GetNativeView(),
                                   sender->GetBoundsInScreen(),
                                   new_contents);

      // If the field is marked as invalid, check if the text is now valid.
      if (decorated->invalid()) {
        decorated->SetInvalid(
            !controller_->InputIsValid(iter->first,
                                       decorated->textfield()->text()));
      }

      break;
    }
  }
}

bool AutofillDialogViews::HandleKeyEvent(views::Textfield* sender,
                                         const ui::KeyEvent& key_event) {
  // TODO(estade): implement.
  return false;
}

void AutofillDialogViews::OnWillChangeFocus(
    views::View* focused_before,
    views::View* focused_now) {
  // TODO(estade): Check + update validity of text field.
  controller_->FocusMoved();
}

void AutofillDialogViews::OnDidChangeFocus(
    views::View* focused_before,
    views::View* focused_now) {}

void AutofillDialogViews::InitChildViews() {
  contents_ = new views::View();
  views::GridLayout* layout = new views::GridLayout(contents_);
  contents_->SetLayoutManager(layout);

  const int single_column_set = 0;
  views::ColumnSet* column_set = layout->AddColumnSet(single_column_set);
  column_set->AddColumn(views::GridLayout::FILL,
                        views::GridLayout::FILL,
                        1,
                        views::GridLayout::USE_PREF,
                        0,
                        0);

  layout->StartRow(0, single_column_set);
  layout->AddView(CreateNotificationArea());

  layout->StartRowWithPadding(0, single_column_set,
                              0, views::kUnrelatedControlVerticalSpacing);
  layout->AddView(CreateDetailsContainer());
}

views::View* AutofillDialogViews::CreateNotificationArea() {
  views::View* notification_area = new views::View();
  notification_area->SetLayoutManager(
      new views::BoxLayout(views::BoxLayout::kHorizontal, 0, 0, 0));
  notification_area->set_background(
      views::Background::CreateSolidBackground(SK_ColorTRANSPARENT));

  DCHECK(!notification_label_);
  notification_label_ = new views::Label();
  notification_label_->SetAutoColorReadabilityEnabled(false);
  notification_area->AddChildView(notification_label_);

  return notification_area;
}

void AutofillDialogViews::UpdateNotificationArea() {
  DCHECK(notification_label_);
  const DialogNotification& notification = controller_->Notification();
  notification_label_->parent()->background()->SetNativeControlColor(
      notification.GetBackgroundColor());
  notification_label_->SetText(notification.display_text());
}

views::View* AutofillDialogViews::CreateDetailsContainer() {
  views::View* view = new views::View();
  // A box layout is used because it respects widget visibility.
  view->SetLayoutManager(
      new views::BoxLayout(views::BoxLayout::kVertical, 0, 0,
                           views::kRelatedControlVerticalSpacing));
  for (DetailGroupMap::iterator iter = detail_groups_.begin();
       iter != detail_groups_.end(); ++iter) {
    CreateDetailsSection(iter->second.section);
    view->AddChildView(iter->second.container);
  }

  return view;
}

void AutofillDialogViews::CreateDetailsSection(DialogSection section) {
  // Inputs container (manual inputs + combobox).
  views::View* inputs_container = CreateInputsContainer(section);

  DetailsGroup* group = GroupForSection(section);
  // Container (holds label + inputs).
  group->container = new SectionContainer(
      controller_->LabelForSection(section),
      inputs_container,
      group->suggested_button);
  UpdateDetailsGroupState(*group);
}

views::View* AutofillDialogViews::CreateInputsContainer(DialogSection section) {
  views::View* inputs_container = new views::View();
  views::GridLayout* layout = new views::GridLayout(inputs_container);
  inputs_container->SetLayoutManager(layout);

  int kColumnSetId = 0;
  views::ColumnSet* column_set = layout->AddColumnSet(kColumnSetId);
  column_set->AddColumn(views::GridLayout::FILL,
                        views::GridLayout::LEADING,
                        1,
                        views::GridLayout::USE_PREF,
                        0,
                        0);
  column_set->AddColumn(views::GridLayout::CENTER,
                        views::GridLayout::LEADING,
                        0,
                        views::GridLayout::USE_PREF,
                        0,
                        0);
  layout->StartRow(0, kColumnSetId);

  // The |info_view| holds |manual_inputs| and |suggested_info|, allowing the
  // dialog toggle which is shown.
  views::View* info_view = new views::View();
  info_view->SetLayoutManager(
      new views::BoxLayout(views::BoxLayout::kVertical, 0, 0, 0));

  if (section == SECTION_SHIPPING) {
    use_billing_for_shipping_ =
        new views::Checkbox(controller_->UseBillingForShippingText());
    use_billing_for_shipping_->SetChecked(true);
    use_billing_for_shipping_->set_listener(this);
    info_view->AddChildView(use_billing_for_shipping_);
  }

  views::View* manual_inputs = InitInputsView(section);
  info_view->AddChildView(manual_inputs);
  views::Label* suggested_info = new views::Label();
  suggested_info->SetHorizontalAlignment(gfx::ALIGN_LEFT);
  info_view->AddChildView(suggested_info);
  layout->AddView(info_view);

  // TODO(estade): Fix the appearance of this button.
  views::ImageButton* menu_button = new views::ImageButton(this);
  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  menu_button->SetImage(views::CustomButton::STATE_NORMAL,
      rb.GetImageSkiaNamed(IDR_AUTOFILL_DIALOG_MENU_BUTTON));
  menu_button->SetImage(views::CustomButton::STATE_PRESSED,
      rb.GetImageSkiaNamed(IDR_AUTOFILL_DIALOG_MENU_BUTTON_P));
  layout->AddView(menu_button);

  DetailsGroup* group = GroupForSection(section);
  group->suggested_button = menu_button;
  group->manual_input = manual_inputs;
  group->suggested_info = suggested_info;
  return inputs_container;
}

// TODO(estade): we should be using Chrome-style constrained window padding
// values.
views::View* AutofillDialogViews::InitInputsView(DialogSection section) {
  const DetailInputs& inputs = controller_->RequestedFieldsForSection(section);
  TextfieldMap* textfields = &GroupForSection(section)->textfields;
  ComboboxMap* comboboxes = &GroupForSection(section)->comboboxes;

  views::View* view = new views::View();
  views::GridLayout* layout = new views::GridLayout(view);
  view->SetLayoutManager(layout);

  for (DetailInputs::const_iterator it = inputs.begin();
       it != inputs.end(); ++it) {
    const DetailInput& input = *it;
    int kColumnSetId = input.row_id;
    views::ColumnSet* column_set = layout->GetColumnSet(kColumnSetId);
    if (!column_set) {
      // Create a new column set and row.
      column_set = layout->AddColumnSet(kColumnSetId);
      if (it != inputs.begin())
        layout->AddPaddingRow(0, views::kRelatedControlVerticalSpacing);
      layout->StartRow(0, kColumnSetId);
    } else {
      // Add a new column to existing row.
      column_set->AddPaddingColumn(0, views::kRelatedControlHorizontalSpacing);
      // Must explicitly skip the padding column since we've already started
      // adding views.
      layout->SkipColumns(1);
    }

    float expand = input.expand_weight;
    column_set->AddColumn(views::GridLayout::FILL,
                          views::GridLayout::BASELINE,
                          expand ? expand : 1,
                          views::GridLayout::USE_PREF,
                          0,
                          0);

    ui::ComboboxModel* input_model =
        controller_->ComboboxModelForAutofillType(input.type);
    // TODO(estade): TextFields and Comboboxes need to be the same height.
    if (input_model) {
      views::Combobox* combobox = new views::Combobox(input_model);
      comboboxes->insert(std::make_pair(&input, combobox));
      layout->AddView(combobox);

      for (int i = 0; i < input_model->GetItemCount(); ++i) {
        if (input.autofilled_value == input_model->GetItemAt(i)) {
          combobox->SetSelectedIndex(i);
          break;
        }
      }
    } else {
      DecoratedTextfield* field = new DecoratedTextfield(
          input.autofilled_value,
          ASCIIToUTF16(input.placeholder_text),
          this);
      textfields->insert(std::make_pair(&input, field));
      layout->AddView(field);
    }
  }

  return view;
}

void AutofillDialogViews::UpdateDetailsGroupState(const DetailsGroup& group) {
  string16 suggestion_text =
      controller_->SuggestionTextForSection(group.section);
  bool show_suggestions = !suggestion_text.empty();
  group.suggested_info->SetVisible(show_suggestions);
  group.suggested_info->SetText(suggestion_text);

  if (group.section == SECTION_SHIPPING) {
    bool show_checkbox = !show_suggestions;
    // When the checkbox is going from hidden to visible, it's because the
    // user clicked "Enter new address". Reset the checkbox to unchecked in this
    // case.
    if (show_checkbox && !use_billing_for_shipping_->visible())
      use_billing_for_shipping_->SetChecked(false);

    use_billing_for_shipping_->SetVisible(show_checkbox);
    group.manual_input->SetVisible(
        show_checkbox && !use_billing_for_shipping_->checked());
  } else {
    group.manual_input->SetVisible(!show_suggestions);
  }

  if (group.container)
    group.container->SetForwardMouseEvents(show_suggestions);

  if (GetWidget())
    GetWidget()->SetSize(GetWidget()->non_client_view()->GetPreferredSize());
}

bool AutofillDialogViews::ValidateForm() {
  bool all_valid = true;
  for (DetailGroupMap::iterator iter = detail_groups_.begin();
       iter != detail_groups_.end(); ++iter) {
    DetailsGroup* group = &iter->second;
    if (group->manual_input->visible()) {
      for (TextfieldMap::iterator iter = group->textfields.begin();
           iter != group->textfields.end(); ++iter) {
        if (!controller_->InputIsValid(iter->first,
                                       iter->second->textfield()->text())) {
          iter->second->SetInvalid(true);
          all_valid = false;
        }
      }
    }
  }
  return all_valid;
}

AutofillDialogViews::DetailsGroup* AutofillDialogViews::GroupForSection(
    DialogSection section) {
  return &detail_groups_.find(section)->second;
}

AutofillDialogViews::DetailsGroup::DetailsGroup(DialogSection section)
    : section(section),
      container(NULL),
      manual_input(NULL),
      suggested_info(NULL),
      suggested_button(NULL) {}

AutofillDialogViews::DetailsGroup::~DetailsGroup() {}

}  // namespace autofill
