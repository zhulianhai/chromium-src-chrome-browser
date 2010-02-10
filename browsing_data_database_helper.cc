// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/browsing_data_database_helper.h"

#include "base/file_util.h"
#include "base/message_loop.h"
#include "chrome/browser/chrome_thread.h"
#include "chrome/browser/profile.h"
#include "third_party/WebKit/WebKit/chromium/public/WebCString.h"
#include "third_party/WebKit/WebKit/chromium/public/WebSecurityOrigin.h"
#include "third_party/WebKit/WebKit/chromium/public/WebString.h"
#include "webkit/database/database_tracker.h"
#include "webkit/glue/webkit_glue.h"

BrowsingDataDatabaseHelper::BrowsingDataDatabaseHelper(Profile* profile)
    : profile_(profile),
      completion_callback_(NULL),
      is_fetching_(false) {
  DCHECK(profile_);
}

BrowsingDataDatabaseHelper::~BrowsingDataDatabaseHelper() {
}

void BrowsingDataDatabaseHelper::StartFetching(
    Callback1<const std::vector<DatabaseInfo>& >::Type* callback) {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::UI));
  DCHECK(!is_fetching_);
  DCHECK(callback);
  is_fetching_ = true;
  database_info_.clear();
  completion_callback_.reset(callback);
  ChromeThread::PostTask(ChromeThread::FILE, FROM_HERE, NewRunnableMethod(
      this, &BrowsingDataDatabaseHelper::FetchDatabaseInfoInFileThread));
}

void BrowsingDataDatabaseHelper::CancelNotification() {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::UI));
  completion_callback_.reset(NULL);
}

void BrowsingDataDatabaseHelper::DeleteDatabase(const std::string& origin,
                                                const std::string& name) {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::UI));
  ChromeThread::PostTask(ChromeThread::FILE, FROM_HERE,NewRunnableMethod(
      this, &BrowsingDataDatabaseHelper::DeleteDatabaseInFileThread, origin,
      name));
}

void BrowsingDataDatabaseHelper::FetchDatabaseInfoInFileThread() {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::FILE));
  std::vector<webkit_database::OriginInfo> origins_info;
  scoped_refptr<webkit_database::DatabaseTracker> tracker =
      profile_->GetDatabaseTracker();
  if (tracker.get() && tracker->GetAllOriginsInfo(&origins_info)) {
    for (std::vector<webkit_database::OriginInfo>::const_iterator ori =
         origins_info.begin(); ori != origins_info.end(); ++ori) {
      scoped_ptr<WebKit::WebSecurityOrigin> web_security_origin(
          WebKit::WebSecurityOrigin::createFromDatabaseIdentifier(
              ori->GetOrigin()));
      std::vector<string16> databases;
      ori->GetAllDatabaseNames(&databases);
      for (std::vector<string16>::const_iterator db = databases.begin();
           db != databases.end(); ++db) {
        FilePath file_path = tracker->GetFullDBFilePath(ori->GetOrigin(), *db);
        file_util::FileInfo file_info;
        if (file_util::GetFileInfo(file_path, &file_info)) {
          database_info_.push_back(DatabaseInfo(
                web_security_origin->host().utf8(),
                UTF16ToUTF8(*db),
                UTF16ToUTF8(ori->GetOrigin()),
                UTF16ToUTF8(ori->GetDatabaseDescription(*db)),
                file_info.size,
                file_info.last_modified));
        }
      }
    }
  }

  ChromeThread::PostTask(ChromeThread::UI, FROM_HERE, NewRunnableMethod(
      this, &BrowsingDataDatabaseHelper::NotifyInUIThread));
}

void BrowsingDataDatabaseHelper::NotifyInUIThread() {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::UI));
  DCHECK(is_fetching_);
  // Note: completion_callback_ mutates only in the UI thread, so it's safe to
  // test it here.
  if (completion_callback_ != NULL)
    completion_callback_->Run(database_info_);
  is_fetching_ = false;
  database_info_.clear();
}

void BrowsingDataDatabaseHelper::DeleteDatabaseInFileThread(
    const std::string& origin,
    const std::string& name) {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::FILE));
  // TODO(jochen): delete the given database.
}
