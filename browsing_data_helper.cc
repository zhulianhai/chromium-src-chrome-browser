// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/browsing_data_helper.h"

#include "base/utf_string_conversions.h"
#include "chrome/common/url_constants.h"
#include "content/public/browser/child_process_security_policy.h"
#include "googleurl/src/gurl.h"
#include "third_party/WebKit/Source/WebKit/chromium/public/platform/WebString.h"

// Static
bool BrowsingDataHelper::IsValidScheme(const std::string& scheme) {
  content::ChildProcessSecurityPolicy* policy =
      content::ChildProcessSecurityPolicy::GetInstance();
  return (policy->IsWebSafeScheme(scheme) &&
          scheme != chrome::kChromeDevToolsScheme &&
          scheme != chrome::kExtensionScheme);
}

// Static
bool BrowsingDataHelper::IsValidScheme(const WebKit::WebString& scheme) {
  return BrowsingDataHelper::IsValidScheme(UTF16ToUTF8(scheme));
}

// Static
bool BrowsingDataHelper::HasValidScheme(const GURL& origin) {
  return BrowsingDataHelper::IsValidScheme(origin.scheme());
}
