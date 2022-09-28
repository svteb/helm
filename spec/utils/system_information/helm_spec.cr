require "kubectl_client"
require "../../spec_helper"
require "colorize"
require "../../../src/utils/utils.cr"
require "../../../src/tasks/utils/system_information/helm.cr"

describe "Helm" do
  describe "global" do
    it "'helm_global_response()' should return the information about the helm installation", tags: ["helm-utils"]  do
      (helm_global_response(true)).should contain("\"v3.")
    end
  end

  describe "local" do
    before_all do
      # If the environment has a good global helm version then local install is skipped.
      # We need the local helm to be able to run the test. So we are force installing it.
      result = KubectlClient::ShellCmd.run("force_install=true ./cnf-testsuite helm_local_install", "helm_local_setup", force_output: true)
      result[:status].success?.should be_true
    end

    it "'helm_local_response()' should return the information about the helm installation", tags: ["helm-utils"]  do
      KubectlClient::ShellCmd.run("ls -R tools/helm", "helm_dir_check", force_output: true)
      (helm_local_response(true)).should contain("\"v3.")
    end

    it "'helm_version()' should return the information about the helm version", tags: ["helm-utils"]  do
      KubectlClient::ShellCmd.run("ls -R tools/helm", "helm_dir_check", force_output: true)
      (helm_version(helm_local_response)).should contain("v3.")
    end

    it "'helm_installations()' should return the information about the helm installation", tags: ["helm-utils"]  do
      (helm_installation(true)).should contain("helm found")
    end

    it "'Helm.helm_gives_k8s_warning?' should pass when k8s config = chmod 700", tags: ["helm-utils"]  do
      (Helm.helm_gives_k8s_warning?(true)).should be_false
    end
  end
end
