// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/prefs/chrome_pref_service_builder.h"

#include "base/bind.h"
#include "base/file_path.h"
#include "base/file_util.h"
#include "base/metrics/histogram.h"
#include "base/prefs/default_pref_store.h"
#include "base/prefs/json_pref_store.h"
#include "chrome/browser/policy/configuration_policy_pref_store.h"
#include "chrome/browser/prefs/command_line_pref_store.h"
#include "chrome/browser/prefs/pref_model_associator.h"
#include "chrome/browser/prefs/pref_notifier_impl.h"
#include "chrome/browser/prefs/pref_service.h"
#include "chrome/browser/prefs/pref_value_store.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/profile_error_dialog.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_thread.h"
#include "grit/chromium_strings.h"
#include "grit/generated_resources.h"

using content::BrowserContext;
using content::BrowserThread;

namespace {

// Shows notifications which correspond to PersistentPrefStore's reading errors.
void HandleReadError(PersistentPrefStore::PrefReadError error) {
  if (error != PersistentPrefStore::PREF_READ_ERROR_NONE) {
    // Failing to load prefs on startup is a bad thing(TM). See bug 38352 for
    // an example problem that this can cause.
    // Do some diagnosis and try to avoid losing data.
    int message_id = 0;
    if (error <= PersistentPrefStore::PREF_READ_ERROR_JSON_TYPE) {
      message_id = IDS_PREFERENCES_CORRUPT_ERROR;
    } else if (error != PersistentPrefStore::PREF_READ_ERROR_NO_FILE) {
      message_id = IDS_PREFERENCES_UNREADABLE_ERROR;
    }

    if (message_id) {
      BrowserThread::PostTask(BrowserThread::UI, FROM_HERE,
                              base::Bind(&ShowProfileErrorDialog, message_id));
    }
    UMA_HISTOGRAM_ENUMERATION("PrefService.ReadError", error,
                              PersistentPrefStore::PREF_READ_ERROR_MAX_ENUM);
  }
}

}  // namespace

// TODO(joi): Find a better home for this.
PrefServiceBase* PrefServiceBase::FromBrowserContext(BrowserContext* context) {
  return static_cast<Profile*>(context)->GetPrefs();
}

ChromePrefServiceBuilder::ChromePrefServiceBuilder() {
  ResetDefaultState();
}

ChromePrefServiceBuilder::~ChromePrefServiceBuilder() {
}

PrefService* ChromePrefServiceBuilder::CreateChromePrefs(
    const FilePath& pref_filename,
    base::SequencedTaskRunner* pref_io_task_runner,
    policy::PolicyService* policy_service,
    PrefStore* extension_prefs,
    bool async) {
#if defined(OS_LINUX)
  // We'd like to see what fraction of our users have the preferences
  // stored on a network file system, as we've had no end of troubles
  // with NFS/AFS.
  // TODO(evanm): remove this once we've collected state.
  file_util::FileSystemType fstype;
  if (file_util::GetFileSystemType(pref_filename.DirName(), &fstype)) {
    UMA_HISTOGRAM_ENUMERATION("PrefService.FileSystemType",
                              static_cast<int>(fstype),
                              file_util::FILE_SYSTEM_TYPE_COUNT);
  }
#endif

#if defined(ENABLE_CONFIGURATION_POLICY)
  using policy::ConfigurationPolicyPrefStore;
  WithManagedPrefs(
      ConfigurationPolicyPrefStore::CreateMandatoryPolicyPrefStore(
          policy_service));
  WithRecommendedPrefs(
      ConfigurationPolicyPrefStore::CreateRecommendedPolicyPrefStore(
          policy_service));
#endif  // ENABLE_CONFIGURATION_POLICY

  WithAsync(async);
  WithExtensionPrefs(extension_prefs);
  WithCommandLinePrefs(
      new CommandLinePrefStore(CommandLine::ForCurrentProcess()));
  WithUserPrefs(new JsonPrefStore(pref_filename, pref_io_task_runner));

  PrefService* pref_service = Create();
  ResetDefaultState();
  return pref_service;
}

void ChromePrefServiceBuilder::ResetDefaultState() {
  WithReadErrorCallback(base::Bind(&HandleReadError));
  WithSyncAssociator(new PrefModelAssociator());
}