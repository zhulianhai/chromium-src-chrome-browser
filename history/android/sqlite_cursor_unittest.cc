// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/history/android/sqlite_cursor.h"

#include <jni.h>

#include "base/android/jni_android.h"
#include "base/android/jni_array.h"
#include "base/android/jni_string.h"
#include "base/time.h"
#include "base/utf_string_conversions.h"
#include "chrome/browser/history/android/android_history_provider_service.h"
#include "chrome/browser/history/android/android_history_types.h"
#include "chrome/browser/history/android/android_time.h"
#include "chrome/browser/history/history.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/common/chrome_constants.h"
#include "chrome/test/base/testing_browser_process.h"
#include "chrome/test/base/testing_profile_manager.h"
#include "chrome/test/base/testing_profile.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/test/test_browser_thread.h"
#include "content/public/test/test_utils.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace {

using base::Bind;
using base::Time;
using content::BrowserThread;
using history::AndroidStatement;
using history::HistoryAndBookmarkRow;
using history::SearchRow;

// The test cases in this file don't test the JNI interface which will be
// covered in Java tests.
class SQLiteCursorTest : public testing::Test,
                         public SQLiteCursor::TestObserver {
 public:
  SQLiteCursorTest()
      : profile_manager_(
          TestingBrowserProcess::GetGlobal()),
        ui_thread_(BrowserThread::UI, &message_loop_),
        file_thread_(BrowserThread::FILE, &message_loop_) {
  }
  virtual ~SQLiteCursorTest() {
  }

 protected:
  virtual void SetUp() OVERRIDE {
    // Setup the testing profile, so the bookmark_model_sql_handler could
    // get the bookmark model from it.
    ASSERT_TRUE(profile_manager_.SetUp());
    // It seems that the name has to be chrome::kInitialProfile, so it
    // could be found by ProfileManager::GetLastUsedProfile().
    testing_profile_ = profile_manager_.CreateTestingProfile(
        chrome::kInitialProfile);

    testing_profile_->CreateBookmarkModel(true);
    testing_profile_->CreateFaviconService();
    testing_profile_->BlockUntilBookmarkModelLoaded();
    testing_profile_->CreateHistoryService(true, false);
    service_.reset(new AndroidHistoryProviderService(testing_profile_));
    hs_ = HistoryServiceFactory::GetForProfile(testing_profile_,
                                               Profile::EXPLICIT_ACCESS);
  }

  virtual void TearDown() OVERRIDE {
    testing_profile_->DestroyHistoryService();
    profile_manager_.DeleteTestingProfile(chrome::kInitialProfile);
    testing_profile_ = NULL;
  }

  // Override SQLiteCursor::TestObserver.
  virtual void OnPostMoveToTask() OVERRIDE {
    MessageLoop::current()->Run();
  }

  virtual void OnGetMoveToResult() OVERRIDE {
    MessageLoop::current()->Quit();
  }

  virtual void OnPostGetFaviconTask() OVERRIDE {
    MessageLoop::current()->Run();
  }

  virtual void OnGetFaviconResult() OVERRIDE {
    MessageLoop::current()->Quit();
  }

 protected:
  TestingProfileManager profile_manager_;
  MessageLoop message_loop_;
  content::TestBrowserThread ui_thread_;
  content::TestBrowserThread file_thread_;
  scoped_ptr<AndroidHistoryProviderService> service_;
  CancelableRequestConsumer cancelable_consumer_;
  TestingProfile* testing_profile_;
  HistoryService* hs_;


 private:
  DISALLOW_COPY_AND_ASSIGN(SQLiteCursorTest);
};

class CallbackHelper : public base::RefCountedThreadSafe<CallbackHelper> {
 public:
  CallbackHelper()
      : success_(false),
        statement_(NULL) {
  }

  bool success() const {
    return success_;
  }

  AndroidStatement* statement() const {
    return statement_;
  }

  void OnInserted(AndroidHistoryProviderService::Handle handle,
                  bool success,
                  int64 id) {
    success_ = success;
    MessageLoop::current()->Quit();
  }

  void OnQueryResult(AndroidHistoryProviderService::Handle handle,
                     bool success,
                     AndroidStatement* statement) {
    success_ = success;
    statement_ = statement;
    MessageLoop::current()->Quit();
  }

 private:
  friend class base::RefCountedThreadSafe<CallbackHelper>;
  ~CallbackHelper() {
  }

  bool success_;
  AndroidStatement* statement_;

  DISALLOW_COPY_AND_ASSIGN(CallbackHelper);
};

}  // namespace

TEST_F(SQLiteCursorTest, Run) {
  HistoryAndBookmarkRow row;
  row.set_raw_url("http://www.google.com/");
  row.set_url(GURL("http://www.google.com/"));
  std::vector<unsigned char> favicon_data;
  favicon_data.push_back(1);
  base::RefCountedBytes *data_bytes =
      base::RefCountedBytes::TakeVector(&favicon_data);
  row.set_favicon(data_bytes);
  row.set_last_visit_time(Time::Now());
  row.set_visit_count(2);
  row.set_title(UTF8ToUTF16("cnn"));
  scoped_refptr<CallbackHelper> callback(new CallbackHelper());

  // Insert a row and verify it succeeded.
  service_->InsertHistoryAndBookmark(row, &cancelable_consumer_,
      Bind(&CallbackHelper::OnInserted, callback.get()));

  MessageLoop::current()->Run();
  EXPECT_TRUE(callback->success());

  std::vector<HistoryAndBookmarkRow::ColumnID> projections;
  projections.push_back(HistoryAndBookmarkRow::URL);
  projections.push_back(HistoryAndBookmarkRow::LAST_VISIT_TIME);
  projections.push_back(HistoryAndBookmarkRow::VISIT_COUNT);
  projections.push_back(HistoryAndBookmarkRow::FAVICON);

  // Query the inserted row.
  service_->QueryHistoryAndBookmarks(projections, std::string(),
      std::vector<string16>(), std::string(), &cancelable_consumer_,
      Bind(&CallbackHelper::OnQueryResult, callback.get()));
  MessageLoop::current()->Run();
  ASSERT_TRUE(callback->success());

  AndroidStatement* statement = callback->statement();
  std::vector<std::string> column_names;
  column_names.push_back(
      HistoryAndBookmarkRow::GetAndroidName(HistoryAndBookmarkRow::URL));
  column_names.push_back(HistoryAndBookmarkRow::GetAndroidName(
      HistoryAndBookmarkRow::LAST_VISIT_TIME));
  column_names.push_back(HistoryAndBookmarkRow::GetAndroidName(
      HistoryAndBookmarkRow::VISIT_COUNT));
  column_names.push_back(HistoryAndBookmarkRow::GetAndroidName(
      HistoryAndBookmarkRow::FAVICON));

  FaviconService* favicon_service = new FaviconService(hs_);

  // Wraps cursor in a block, so the destructor will be called after that.
  {
    SQLiteCursor cursor(column_names, statement, service_.get(),
                        favicon_service);
    cursor.set_test_observer(this);
    JNIEnv* env = base::android::AttachCurrentThread();
    EXPECT_EQ(1, cursor.GetCount(env, NULL));
    EXPECT_EQ(0, cursor.MoveTo(env, NULL, 0));
    EXPECT_EQ(row.url().spec(), base::android::ConvertJavaStringToUTF8(
        cursor.GetString(env, NULL, 0)).c_str());
    EXPECT_EQ(history::ToDatabaseTime(row.last_visit_time()),
              cursor.GetLong(env, NULL, 1));
    EXPECT_EQ(row.visit_count(), cursor.GetInt(env, NULL, 2));
    base::android::ScopedJavaLocalRef<jbyteArray> data =
        cursor.GetBlob(env, NULL, 3);
    std::vector<uint8> out;
    base::android::JavaByteArrayToByteVector(env, data.obj(), &out);
    EXPECT_EQ(data_bytes->data().size(), out.size());
    EXPECT_EQ(data_bytes->data()[0], out[0]);
  }

  // Cursor's destructor post the task in UI thread, run Message loop to release
  // the statement etc.
  content::RunAllPendingInMessageLoop();
}
