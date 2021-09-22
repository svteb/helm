require "totem"
require "colorize"
require "./cnf_manager.cr"
require "halite"

module OPA 

  OPA_KIND_NAME="requiretags"
  OPA_VIOLATION_NAME="block-latest-tag"
  def self.find_non_versioned_pod(pod_name)
    LOGGING.info "OPA.find_non_versioned_pod: #{pod_name}"
    resp = KubectlClient.describe(OPA_KIND_NAME, OPA_VIOLATION_NAME)
    output = resp[:output]
    match = output.to_s.match(/.*Pod #{pod_name}, it uses an image tag that is not versioned.*/)
    LOGGING.info "OPA Pod Data: #{match}"
    if match
      true
    else
      false
    end
  end
end
