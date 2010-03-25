// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <algorithm>
#include <functional>

#include "base/logging.h"
#include "base/task.h"
#include "chrome/browser/chrome_thread.h"
#include "chrome/browser/sync/glue/data_type_controller.h"
#include "chrome/browser/sync/glue/data_type_manager_impl.h"
#include "chrome/browser/sync/glue/sync_backend_host.h"
#include "chrome/common/notification_details.h"
#include "chrome/common/notification_service.h"
#include "chrome/common/notification_source.h"

namespace browser_sync {

namespace {

static const syncable::ModelType kStartOrder[] = {
  syncable::BOOKMARKS,
  syncable::PREFERENCES,
  syncable::AUTOFILL,
  syncable::TYPED_URLS,
};

// Comparator used when sorting data type controllers.
class SortComparator : public std::binary_function<DataTypeController*,
                                                   DataTypeController*,
                                                   bool> {
 public:
  explicit SortComparator(std::map<syncable::ModelType, int>* order)
      : order_(order) { }

  // Returns true if lhs preceeds rhs.
  bool operator() (DataTypeController* lhs, DataTypeController* rhs) {
    return (*order_)[lhs->type()] < (*order_)[rhs->type()];
  }

 private:
  std::map<syncable::ModelType, int>* order_;
};

}  // namespace

DataTypeManagerImpl::DataTypeManagerImpl(
    SyncBackendHost* backend,
    const DataTypeController::TypeMap& controllers)
    : backend_(backend),
      controllers_(controllers),
      state_(DataTypeManager::STOPPED),
      current_dtc_(NULL) {
  DCHECK(backend_);
  DCHECK_GT(arraysize(kStartOrder), 0U);
  // Ensure all data type controllers are stopped.
  for (DataTypeController::TypeMap::const_iterator it = controllers_.begin();
       it != controllers_.end(); ++it) {
    DCHECK_EQ(DataTypeController::NOT_RUNNING, (*it).second->state());
  }

  // Build a ModelType -> order map for sorting.
  for (int i = 0; i < static_cast<int>(arraysize(kStartOrder)); i++)
    start_order_[kStartOrder[i]] = i;
}

void DataTypeManagerImpl::Configure(const TypeSet& desired_types) {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::UI));
  if (state_ == STOPPING) {
    // You can not set a configuration while stopping.
    LOG(ERROR) << "Configuration set while stopping.";
    return;
  }

  // Add any data type controllers into the needs_start_ list that are
  // currently NOT_RUNNING or STOPPING.
  needs_start_.clear();
  for (TypeSet::const_iterator it = desired_types.begin();
       it != desired_types.end(); ++it) {
    DataTypeController* dtc = controllers_[*it];
    if (dtc && (dtc->state() == DataTypeController::NOT_RUNNING ||
                dtc->state() == DataTypeController::STOPPING)) {
      needs_start_.push_back(dtc);
      LOG(INFO) << "Will start " << dtc->name();
    }
  }
  // Sort these according to kStartOrder.
  std::sort(needs_start_.begin(),
            needs_start_.end(),
            SortComparator(&start_order_));

  // Add any data type controllers into that needs_stop_ list that are
  // currently MODEL_STARTING, ASSOCIATING, or RUNNING.
  needs_stop_.clear();
  for (DataTypeController::TypeMap::const_iterator it = controllers_.begin();
       it != controllers_.end(); ++it) {
    DataTypeController* dtc = (*it).second;
    if (desired_types.count(dtc->type()) == 0 && (
            dtc->state() == DataTypeController::MODEL_STARTING ||
            dtc->state() == DataTypeController::ASSOCIATING ||
            dtc->state() == DataTypeController::RUNNING)) {
      needs_stop_.push_back(dtc);
      LOG(INFO) << "Will stop " << dtc->name();
    }
  }
  // Sort these according to kStartOrder.
  std::sort(needs_stop_.begin(),
            needs_stop_.end(),
            SortComparator(&start_order_));

  // If nothing changed, we're done.
  if (needs_start_.size() == 0 && needs_stop_.size() == 0) {
    state_ = CONFIGURED;
    NotifyStart();
    NotifyDone(OK);
    return;
  }

  Restart();
}

void DataTypeManagerImpl::Restart() {
  LOG(INFO) << "Restarting...";
  // If we are currently waiting for an asynchronous process to
  // complete, change our state to RESTARTING so those processes know
  // that we want to start over when they finish.
  if (state_ == DOWNLOAD_PENDING || state_ == PAUSE_PENDING ||
      state_ == CONFIGURING || state_ == RESUME_PENDING) {
    state_ = RESTARTING;
    return;
  }

  DCHECK(state_ == STOPPED || state_ == RESTARTING || state_ == CONFIGURED);
  current_dtc_ = NULL;

  // Starting from a "steady state" (stopped or configured) state
  // should send a start notification.
  if (state_ == STOPPED || state_ == CONFIGURED)
    NotifyStart();

  // Stop requested data types.
  for (size_t i = 0; i < needs_stop_.size(); ++i) {
    LOG(INFO) << "Stopping " << needs_stop_[i]->name();
    needs_stop_[i]->Stop();
  }
  needs_stop_.clear();

  // TODO(sync): Get updates for new data types here.

  // Pause the sync backend before starting the data types.
  state_ = PAUSE_PENDING;
  PauseSyncer();
}

void DataTypeManagerImpl::StartNextType() {
  // If there are any data types left to start, start the one at the
  // front of the list.
  if (needs_start_.size() > 0) {
    current_dtc_ = needs_start_[0];
    LOG(INFO) << "Starting " << current_dtc_->name();
    current_dtc_->Start(
        true,
        NewCallback(this, &DataTypeManagerImpl::TypeStartCallback));
    return;
  }

  // If no more data types need starting, we're done.  Resume the sync
  // backend to finish.
  DCHECK_EQ(state_, CONFIGURING);
  state_ = RESUME_PENDING;
  ResumeSyncer();
}

void DataTypeManagerImpl::TypeStartCallback(
    DataTypeController::StartResult result) {
  // When the data type controller invokes this callback, it must be
  // on the UI thread.
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::UI));
  DCHECK(current_dtc_);

  // If configuration changed while this data type was starting, we
  // need to reset.  Resume the syncer.
  if (state_ == RESTARTING) {
    ResumeSyncer();
    return;
  }

  // We're done with the data type at the head of the list -- remove it.
  DataTypeController* started_dtc = current_dtc_;
  DCHECK(needs_start_.size());
  DCHECK_EQ(needs_start_[0], started_dtc);
  needs_start_.erase(needs_start_.begin());
  current_dtc_ = NULL;

  // If we reach this callback while stopping, this means that
  // DataTypeManager::Stop() was called while the current data type
  // was starting.  Now that it has finished starting, we can finish
  // stopping the DataTypeManager.  This is considered an ABORT.
  if (state_ == STOPPING) {
    FinishStop();
    NotifyDone(ABORTED);
    return;
  }

  // If our state_ is STOPPED, we have already stopped all of the data
  // types.  We should not be getting callbacks from stopped data types.
  if (state_ == STOPPED) {
    LOG(ERROR) << "Start callback called by stopped data type!";
    return;
  }

  // If the type started normally, continue to the next type.
  if (result == DataTypeController::OK ||
      result == DataTypeController::OK_FIRST_RUN) {
    LOG(INFO) << "Started " << started_dtc->name();
    StartNextType();
    return;
  }

  // Any other result is a fatal error.  Shut down any types we've
  // managed to start up to this point and pass the result to the
  // callback.
  LOG(INFO) << "Failed " << started_dtc->name();
  FinishStop();
  ConfigureResult configure_result = DataTypeManager::ABORTED;
  switch (result) {
    case DataTypeController::ABORTED:
      configure_result = DataTypeManager::ABORTED;
      break;
    case DataTypeController::ASSOCIATION_FAILED:
      configure_result = DataTypeManager::ASSOCIATION_FAILED;
      break;
    case DataTypeController::UNRECOVERABLE_ERROR:
      configure_result = DataTypeManager::UNRECOVERABLE_ERROR;
      break;
    default:
      NOTREACHED();
      break;
  }
  NotifyDone(configure_result);
}

void DataTypeManagerImpl::Stop() {
  DCHECK(ChromeThread::CurrentlyOn(ChromeThread::UI));
  if (state_ == STOPPED)
    return;

  // If we are currently configuring, then the current type is in a
  // partially started state.  Abort the startup of the current type,
  // which will synchronously invoke the start callback.
  if (state_ == CONFIGURING) {
    state_ = STOPPING;
    current_dtc_->Stop();
    return;
  }

  // If Stop() is called while waiting for pause or resume, we no
  // longer care about this.
  if (state_ == PAUSE_PENDING)
    RemoveObserver(NotificationType::SYNC_PAUSED);
  if (state_ == RESUME_PENDING)
    RemoveObserver(NotificationType::SYNC_RESUMED);

  state_ = STOPPING;
  FinishStop();
}

void DataTypeManagerImpl::FinishStop() {
  DCHECK(state_== CONFIGURING ||
         state_ == STOPPING ||
         state_ == PAUSE_PENDING ||
         state_ == RESUME_PENDING);
  // Simply call the Stop() method on all running data types.
  for (DataTypeController::TypeMap::const_iterator it = controllers_.begin();
       it != controllers_.end(); ++it) {
    DataTypeController* dtc = (*it).second;
    if (dtc->state() == DataTypeController::RUNNING) {
      dtc->Stop();
      LOG(INFO) << "Stopped " << dtc->name();
    }
  }
  state_ = STOPPED;
}

void DataTypeManagerImpl::Observe(NotificationType type,
                                  const NotificationSource& source,
                                  const NotificationDetails& details) {
  switch (type.value) {
    case NotificationType::SYNC_PAUSED:
      DCHECK(state_ == PAUSE_PENDING || state_ == RESTARTING);
      RemoveObserver(NotificationType::SYNC_PAUSED);

      // If the state changed to RESTARTING while waiting to be
      // paused, resume the syncer so we can restart.
      if (state_ == RESTARTING) {
        ResumeSyncer();
        return;
      }

      state_ = CONFIGURING;
      StartNextType();
      break;
    case NotificationType::SYNC_RESUMED:
      DCHECK(state_ == RESUME_PENDING || state_ == RESTARTING);
      RemoveObserver(NotificationType::SYNC_RESUMED);

      // If we are resuming because of a restart, continue the restart.
      if (state_ == RESTARTING) {
        Restart();
        return;
      }

      state_ = CONFIGURED;
      NotifyDone(OK);
      break;
    default:
      NOTREACHED();
  }
}

void DataTypeManagerImpl::AddObserver(NotificationType type) {
  notification_registrar_.Add(this,
                              type,
                              NotificationService::AllSources());
}

void DataTypeManagerImpl::RemoveObserver(NotificationType type) {
  notification_registrar_.Remove(this,
                                 type,
                                 NotificationService::AllSources());
}

void DataTypeManagerImpl::NotifyStart() {
  NotificationService::current()->Notify(
      NotificationType::SYNC_CONFIGURE_START,
      NotificationService::AllSources(),
      NotificationService::NoDetails());
}

void DataTypeManagerImpl::NotifyDone(ConfigureResult result) {
  NotificationService::current()->Notify(
      NotificationType::SYNC_CONFIGURE_DONE,
      NotificationService::AllSources(),
      Details<ConfigureResult>(&result));
}

void DataTypeManagerImpl::ResumeSyncer() {
  AddObserver(NotificationType::SYNC_RESUMED);
  if (!backend_->RequestResume()) {
    RemoveObserver(NotificationType::SYNC_RESUMED);
    FinishStop();
    NotifyDone(UNRECOVERABLE_ERROR);
  }
}

void DataTypeManagerImpl::PauseSyncer() {
  AddObserver(NotificationType::SYNC_PAUSED);
  if (!backend_->RequestPause()) {
    RemoveObserver(NotificationType::SYNC_PAUSED);
    FinishStop();
    NotifyDone(UNRECOVERABLE_ERROR);
  }
}

}  // namespace browser_sync
