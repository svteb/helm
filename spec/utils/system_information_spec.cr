require "kubectl_client"
require "../spec_helper"
require "colorize"
require "../../src/utils/utils.cr"
require "../../src/utils/system_information.cr"

describe "Helm" do
  describe "global" do
    before_all do
      helm_local_cleanup
    end

    it "local helm should not be detected", tags: ["helm-utils"]  do
      (Helm::BinarySingleton.local_helm_exists?).should be_false
    end

    it "'SystemInfo::Helm.global_helm_installed?' should return the information about the helm installation", tags: ["helm-utils"]  do
      (SystemInfo::Helm.global_helm_installed?).should be_true
    end
    
    it "'helm_global_response()' should return the information about the helm installation", tags: ["helm-utils"]  do
      (helm_global_response(true)).should contain("\"v3.")
    end

    it "'helm_installations()' should return the information about the helm installation", tags: ["helm-utils"]  do
      (helm_installation(true)).should contain("helm found")
    end
  end

  describe "local" do
    before_all do
      install_local_helm
    end
    
    it "'SystemInfo::Helm.local_helm_installed?' should return the information about the helm installation", tags: ["helm-utils"]  do
      (SystemInfo::Helm.local_helm_installed?).should be_true
    end

    it "'helm_local_response()' should return the information about the helm installation", tags: ["helm-utils"]  do
      Helm::ShellCmd.run("ls -R tools/helm", "helm_dir_check", force_output: true)
      (helm_local_response(true)).should contain("\"v3.")
    end
    
    it "'helm_version()' should return the information about the helm version", tags: ["helm-utils"]  do
      Helm::ShellCmd.run("ls -R tools/helm", "helm_dir_check", force_output: true)
      (helm_version(helm_local_response)).should contain("v3.")
    end

    it "local helm should be detected", tags: ["helm-utils"]  do
      (Helm::BinarySingleton.local_helm_exists?).should be_true
    end 
  end
end
