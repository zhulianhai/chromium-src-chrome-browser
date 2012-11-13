// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/spellchecker/spellcheck_service.h"

#include "base/platform_file.h"
#include "base/string_split.h"
#include "base/synchronization/waitable_event.h"
#include "chrome/browser/api/prefs/pref_member.h"
#include "chrome/browser/prefs/pref_service.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/spellchecker/spellcheck_host_metrics.h"
#include "chrome/browser/spellchecker/spellcheck_hunspell_dictionary.h"
#include "chrome/browser/spellchecker/spellcheck_factory.h"
#include "chrome/browser/spellchecker/spellcheck_platform_mac.h"
#include "chrome/common/pref_names.h"
#include "chrome/common/spellcheck_messages.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/notification_service.h"
#include "content/public/browser/notification_types.h"
#include "content/public/browser/render_process_host.h"
#include "ipc/ipc_platform_file.h"

using content::BrowserThread;
using chrome::spellcheck_common::WordList;

// TODO(rlp): I do not like globals, but keeping thsese for now during
// transition.
// An event used by browser tests to receive status events from this class and
// its derived classes.
base::WaitableEvent* g_status_event = NULL;
SpellcheckService::EventType g_status_type =
    SpellcheckService::BDICT_NOTINITIALIZED;

SpellcheckService::SpellcheckService(Profile* profile)
    : profile_(profile),
      weak_ptr_factory_(ALLOW_THIS_IN_INITIALIZER_LIST(this)) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));
  PrefService* prefs = profile_->GetPrefs();
  pref_change_registrar_.Init(prefs);
  pref_change_registrar_.Add(prefs::kSpellCheckDictionary, this);
  pref_change_registrar_.Add(prefs::kEnableSpellCheck, this);
  pref_change_registrar_.Add(prefs::kEnableAutoSpellCorrect, this);

  hunspell_dictionary_.reset(new SpellcheckHunspellDictionary(
      profile, prefs->GetString(prefs::kSpellCheckDictionary),
      profile->GetRequestContext(), this));
  // TODO(rlp): This should be the load function so we can loop through all
  // dictionaries easily.
  hunspell_dictionary_->Initialize();

  custom_dictionary_.reset(new SpellcheckCustomDictionary(profile_));
  custom_dictionary_->Load();

  registrar_.Add(weak_ptr_factory_.GetWeakPtr(),
                 content::NOTIFICATION_RENDERER_PROCESS_CREATED,
                 content::NotificationService::AllSources());

}

SpellcheckService::~SpellcheckService() {
  // Remove pref observers
  pref_change_registrar_.RemoveAll();
}

// static
int SpellcheckService::GetSpellCheckLanguages(
    Profile* profile,
    std::vector<std::string>* languages) {
  StringPrefMember accept_languages_pref;
  StringPrefMember dictionary_language_pref;
  accept_languages_pref.Init(prefs::kAcceptLanguages, profile->GetPrefs(),
                             NULL);
  dictionary_language_pref.Init(prefs::kSpellCheckDictionary,
                                profile->GetPrefs(), NULL);
  std::string dictionary_language = dictionary_language_pref.GetValue();

  // Now scan through the list of accept languages, and find possible mappings
  // from this list to the existing list of spell check languages.
  std::vector<std::string> accept_languages;

#if defined(OS_MACOSX)
  if (spellcheck_mac::SpellCheckerAvailable())
    spellcheck_mac::GetAvailableLanguages(&accept_languages);
  else
    base::SplitString(accept_languages_pref.GetValue(), ',', &accept_languages);
#else
  base::SplitString(accept_languages_pref.GetValue(), ',', &accept_languages);
#endif  // !OS_MACOSX

  GetSpellCheckLanguagesFromAcceptLanguages(
      accept_languages, dictionary_language, languages);

  for (size_t i = 0; i < languages->size(); ++i) {
    if ((*languages)[i] == dictionary_language)
      return i;
  }
  return -1;
}

// static
void SpellcheckService::GetSpellCheckLanguagesFromAcceptLanguages(
    const std::vector<std::string>& accept_languages,
    const std::string& dictionary_language,
    std::vector<std::string>* languages) {
  // The current dictionary language should be there.
  languages->push_back(dictionary_language);

  for (std::vector<std::string>::const_iterator i = accept_languages.begin();
       i != accept_languages.end(); ++i) {
    std::string language =
        chrome::spellcheck_common::GetCorrespondingSpellCheckLanguage(*i);
    if (!language.empty() &&
        std::find(languages->begin(), languages->end(), language) ==
        languages->end()) {
      languages->push_back(language);
    }
  }
}

// static
bool SpellcheckService::SignalStatusEvent(
    SpellcheckService::EventType status_type) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::FILE));

  if (!g_status_event)
    return false;
  g_status_type = status_type;
  g_status_event->Signal();
  return true;
}

// static
void SpellcheckService::AttachStatusEvent(base::WaitableEvent* status_event) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  g_status_event = status_event;
}

// static
SpellcheckService::EventType SpellcheckService::WaitStatusEvent() {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  if (g_status_event)
    g_status_event->Wait();
  return g_status_type;
}

void SpellcheckService::Initialize() {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));
  hunspell_dictionary_->Initialize();
}

void SpellcheckService::StartRecordingMetrics(bool spellcheck_enabled) {
  metrics_.reset(new SpellCheckHostMetrics());
  metrics_->RecordEnabledStats(spellcheck_enabled);
}

void SpellcheckService::InitForRenderer(content::RenderProcessHost* process) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  Profile* profile = Profile::FromBrowserContext(process->GetBrowserContext());
  if (SpellcheckServiceFactory::GetForProfile(profile) != this)
    return;

  PrefService* prefs = profile->GetPrefs();
  IPC::PlatformFileForTransit file = IPC::InvalidPlatformFileForTransit();

  if (hunspell_dictionary_->GetDictionaryFile() !=
      base::kInvalidPlatformFileValue) {
#if defined(OS_POSIX)
    file = base::FileDescriptor(hunspell_dictionary_->GetDictionaryFile(),
                                false);
#elif defined(OS_WIN)
    BOOL ok = ::DuplicateHandle(::GetCurrentProcess(),
                                hunspell_dictionary_->GetDictionaryFile(),
                                process->GetHandle(),
                                &file,
                                0,
                                false,
                                DUPLICATE_SAME_ACCESS);
    DCHECK(ok) << ::GetLastError();
#endif
  }

  WordList custom_words = GetCustomDictionary()->GetCustomWords();

  process->Send(new SpellCheckMsg_Init(
      file,
      custom_words,
      hunspell_dictionary_->GetLanguage(),
      prefs->GetBoolean(prefs::kEnableAutoSpellCorrect)));
}

void SpellcheckService::AddWord(const std::string& word) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  GetCustomDictionary()->CustomWordAddedLocally(word);

  // TODO(rlp): pass these on to the correct dictionary.
  BrowserThread::PostTaskAndReply(BrowserThread::FILE, FROM_HERE,
      base::Bind(&SpellcheckService::WriteWordToCustomDictionary,
                 base::Unretained(this), word),
      base::Bind(&SpellcheckService::AddWordComplete,
                 weak_ptr_factory_.GetWeakPtr(), word));
}

const WordList& SpellcheckService::GetCustomWords() {
  return GetCustomDictionary()->GetCustomWords();

}

void SpellcheckService::CustomWordAddedLocally(const std::string& word) {
  GetCustomDictionary()->CustomWordAddedLocally(word);
}

void SpellcheckService::LoadDictionaryIntoCustomWordList(
    WordList* custom_words){
  GetCustomDictionary()->LoadDictionaryIntoCustomWordList(custom_words);
}

void SpellcheckService::WriteWordToCustomDictionary(const std::string& word){
  GetCustomDictionary()->WriteWordToCustomDictionary(word);
}

void SpellcheckService::Observe(int type,
                                const content::NotificationSource& source,
                                const content::NotificationDetails& details) {
  DCHECK(type == content::NOTIFICATION_RENDERER_PROCESS_CREATED);
  content::RenderProcessHost* process =
      content::Source<content::RenderProcessHost>(source).ptr();
  InitForRenderer(process);
}

void SpellcheckService::OnPreferenceChanged(PrefServiceBase* prefs,
                                            const std::string& pref_name_in) {
  DCHECK(prefs);
  if (pref_name_in == prefs::kSpellCheckDictionary ||
      pref_name_in == prefs::kEnableSpellCheck) {
    InformProfileOfInitializationWithCustomWords(NULL);
  } else if (pref_name_in == prefs::kEnableAutoSpellCorrect) {
    bool enabled = prefs->GetBoolean(prefs::kEnableAutoSpellCorrect);
    for (content::RenderProcessHost::iterator i(
             content::RenderProcessHost::AllHostsIterator());
         !i.IsAtEnd(); i.Advance()) {
      content::RenderProcessHost* process = i.GetCurrentValue();
      process->Send(new SpellCheckMsg_EnableAutoSpellCorrect(enabled));
    }
  }
}

SpellCheckHostMetrics* SpellcheckService::GetMetrics() const {
  return metrics_.get();
}

SpellcheckCustomDictionary* SpellcheckService::GetCustomDictionary() {
  return custom_dictionary_.get();
}

bool SpellcheckService::IsReady() const {
  return hunspell_dictionary_->IsReady();
}

bool SpellcheckService::IsUsingPlatformChecker() const {
  return hunspell_dictionary_->IsUsingPlatformChecker();
}

const base::PlatformFile& SpellcheckService::GetDictionaryFile() const {
  return hunspell_dictionary_->GetDictionaryFile();
}

const std::string& SpellcheckService::GetLanguage() const {
  return hunspell_dictionary_->GetLanguage();
}

void SpellcheckService::AddWordComplete(const std::string& word) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  for (content::RenderProcessHost::iterator i(
          content::RenderProcessHost::AllHostsIterator());
       !i.IsAtEnd(); i.Advance()) {
    i.GetCurrentValue()->Send(new SpellCheckMsg_WordAdded(word));
  }
}

// TODO(rlp): rename to something more logical.
void SpellcheckService::InformProfileOfInitializationWithCustomWords(
    WordList* custom_words) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  if (custom_words) {
    GetCustomDictionary()->SetCustomWordList(custom_words);
  }

  for (content::RenderProcessHost::iterator i(
          content::RenderProcessHost::AllHostsIterator());
       !i.IsAtEnd(); i.Advance()) {
    content::RenderProcessHost* process = i.GetCurrentValue();
    if (process)
      InitForRenderer(process);
  }
}