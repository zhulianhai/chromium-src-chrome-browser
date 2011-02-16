// Copyright (c) 2011 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_POLICY_CLOUD_POLICY_CACHE_H_
#define CHROME_BROWSER_POLICY_CLOUD_POLICY_CACHE_H_

#include <string>

#include "base/file_path.h"
#include "base/gtest_prod_util.h"
#include "base/ref_counted.h"
#include "base/scoped_ptr.h"
#include "base/synchronization/lock.h"
#include "base/time.h"
#include "chrome/browser/policy/configuration_policy_provider.h"
#include "chrome/browser/policy/proto/device_management_backend.pb.h"
#include "policy/configuration_policy_type.h"

class DictionaryValue;
class ListValue;
class Value;

using google::protobuf::RepeatedPtrField;

namespace policy {

namespace em = enterprise_management;

// Keeps the authoritative copy of cloud policy information as read from the
// persistence file or determined by the policy backend. The cache doesn't talk
// to the service directly, but receives updated policy information through
// SetPolicy() calls, which is then persisted and decoded into the internal
// Value representation chrome uses.
class CloudPolicyCache {
 public:
  typedef ConfigurationPolicyProvider::PolicyMapType PolicyMapType;

  explicit CloudPolicyCache(const FilePath& backing_file_path);
  ~CloudPolicyCache();

  // Loads policy information from the backing file. Non-existing or erroneous
  // cache files are ignored.
  void LoadPolicyFromFile();

  // Resets the policy information. Returns true if the new policy is different
  // from the previously stored policy.
  bool SetPolicy(const em::CloudPolicyResponse& policy);
  bool SetDevicePolicy(const em::DevicePolicyResponse& policy);

  // Gets the policy information. Ownership of the return value is transferred
  // to the caller.
  DictionaryValue* GetDevicePolicy();
  const PolicyMapType* GetMandatoryPolicy() const;
  const PolicyMapType* GetRecommendedPolicy() const;

  void SetUnmanaged();
  bool is_unmanaged() const {
    return is_unmanaged_;
  }

  // Returns the time at which the policy was last fetched.
  base::Time last_policy_refresh_time() const {
    return last_policy_refresh_time_;
  }

  // Returns true if this cache holds (old-style) device policy that should be
  // given preference over (new-style) mandatory/recommended policy.
  bool has_device_policy() const {
    return has_device_policy_;
  }

 private:
  friend class CloudPolicyCacheTest;
  friend class DeviceManagementPolicyCacheDecodeTest;

  // Decodes a CloudPolicyResponse into two (ConfigurationPolicyType -> Value*)
  // maps and a timestamp. Also performs verification, returns NULL if any
  // check fails.
  static bool DecodePolicyResponse(
      const em::CloudPolicyResponse& policy_response,
      PolicyMapType* mandatory,
      PolicyMapType* recommended,
      base::Time* timestamp);

  // Returns true if |certificate_chain| is trusted and a |signature| created
  // from it matches |data|.
  static bool VerifySignature(
      const std::string& signature,
      const std::string& data,
      const RepeatedPtrField<std::string>& certificate_chain);

  // Returns true if |a| equals |b|.
  static bool Equals(const PolicyMapType& a, const PolicyMapType& b);
  // Helper function for the above.
  static bool MapEntryEquals(const PolicyMapType::value_type& a,
                             const PolicyMapType::value_type& b);

  // Decodes an int64 value. Checks whether the passed value fits the numeric
  // limits of the value representation. Returns a value (ownership is
  // transferred to the caller) on success, NULL on failure.
  static Value* DecodeIntegerValue(google::protobuf::int64 value);

  // Decode a GenericValue message to the Value representation used internally.
  // Returns NULL if |value| is invalid (i.e. contains no actual value).
  static Value* DecodeValue(const em::GenericValue& value);

  // Decodes a policy message and returns it in Value representation. Ownership
  // of the returned dictionary is transferred to the caller.
  static DictionaryValue* DecodeDevicePolicy(
      const em::DevicePolicyResponse& response);

  // The file in which we store a cached version of the policy information.
  const FilePath backing_file_path_;

  // Protects both |mandatory_policy_| and |recommended_policy_| as well as
  // |device_policy_|.
  base::Lock lock_;

  // Policy key-value information.
  PolicyMapType mandatory_policy_;
  PolicyMapType recommended_policy_;
  scoped_ptr<DictionaryValue> device_policy_;

  // Tracks whether the store received a SetPolicy() call, which overrides any
  // information loaded from the file.
  bool fresh_policy_;

  bool is_unmanaged_;

  // Tracks whether the cache currently stores |device_policy_| that should be
  // given preference over |mandatory_policy_| and |recommended_policy_|.
  bool has_device_policy_;

  // The time at which the policy was last refreshed.
  base::Time last_policy_refresh_time_;
};

}  // namespace policy

#endif  // CHROME_BROWSER_POLICY_CLOUD_POLICY_CACHE_H_
