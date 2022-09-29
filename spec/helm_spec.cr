require "./spec_helper.cr"

describe "Helm" do
  describe "global" do
    before_all do
      helm_local_cleanup
    end

    it "local helm should not be detected", tags: ["helm-utils"]  do
      (Helm::BinarySingleton.local_helm_exists?).should be_false
    end

    it "'Helm.helm_repo_add' should work", tags: ["helm-utils"]  do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      (stable_repo).should be_true
    end

    it "'Helm.helm_gives_k8s_warning?' should pass when k8s config = chmod 700", tags: ["helm-utils"]  do
      (Helm.helm_gives_k8s_warning?(true)).should be_false
    end
  end

  describe "local" do
    before_all do
      install_local_helm
    end

    it "local helm should be detected", tags: ["helm-utils"]  do
      (Helm::BinarySingleton.local_helm_exists?).should be_true
    end
    
    it "'Helm.helm_repo_add' should work", tags: ["helm-utils"]  do
      stable_repo = Helm.helm_repo_add("stable", "https://cncf.gitlab.io/stable")
      Log.for("verbose").debug { "stable repo add: #{stable_repo}" }
      (stable_repo).should be_true
    end

    it "'Helm.helm_gives_k8s_warning?' should pass when k8s config = chmod 700", tags: ["helm-utils"]  do
      (Helm.helm_gives_k8s_warning?(true)).should be_false
    end
  end
end
