require "totem"
require "colorize"
require "./cnf_manager.cr"
require "halite"

module KubectlClient 
  WORKLOAD_RESOURCES = {deployment: "Deployment", 
                        service: "Service", 
                        pod: "Pod", 
                        replicaset: "ReplicaSet", 
                        statefulset: "StatefulSet", 
                        daemonset: "DaemonSet"}

  # https://www.capitalone.com/tech/cloud/container-runtime/
  OCI_RUNTIME_REGEX = /containerd|docker|runc|railcar|crun|rkt|gviso|nabla|runv|clearcontainers|kata|cri-o/i
  module Rollout
    def self.status(deployment_name, timeout="30s")
      rollout = `kubectl rollout status deployment/#{deployment_name} --timeout=#{timeout}`
      rollout_status = $?.success?
      LOGGING.debug "#{rollout}"
      LOGGING.debug "rollout? #{rollout_status}"
      $?.success?
    end
    def self.resource_status(kind, resource_name, timeout="30s")
      rollout = `kubectl rollout status #{kind}/#{resource_name} --timeout=#{timeout}`
      rollout_status = $?.success?
      LOGGING.debug "#{rollout}"
      LOGGING.debug "rollout? #{rollout_status}"
      $?.success?
    end

    def self.undo(deployment_name)
      rollback = `kubectl rollout undo deployment/#{deployment_name}`
      rollback_status = $?.success?
      LOGGING.debug "#{rollback}"
      LOGGING.debug "rollback? #{rollback_status}"
      $?.success?
    end
  end
  module Apply
    def self.file(file_name) : Bool
      LOGGING.info "apply file: #{file_name}"
      apply = `kubectl apply -f #{file_name}`
      apply_status = $?.success?
      LOGGING.debug "kubectl apply resp: #{apply}"
      LOGGING.debug "apply? #{apply_status}"
      apply_status
    end
  end
  module Delete
    def self.file(file_name)
      delete = `kubectl delete -f #{file_name}`
      delete_status = $?.success?
      LOGGING.debug "#{delete}"
      LOGGING.debug "delete? #{delete_status}"
      delete_status
    end
  end
  module Set
    def self.image(deployment_name, container_name, image_name, version_tag=nil)
      #TODO check if image exists in repo? DockerClient::Get.image and image_by_tags
      if version_tag
        # use --record to have history
        resp  = `kubectl set image deployment/#{deployment_name} #{container_name}=#{image_name}:#{version_tag} --record`
      else
        resp  = `kubectl set image deployment/#{deployment_name} #{container_name}=#{image_name} --record`
      end
      LOGGING.debug "set image: #{resp}" 
      $?.success?
    end
  end
  module Get 
    def self.privileged_containers(namespace="--all-namespaces")
      privileged_response = `kubectl get pods #{namespace} -o jsonpath='{.items[*].spec.containers[?(@.securityContext.privileged==true)].name}'`
      # TODO parse this as json
      resp = privileged_response.to_s.split(" ").uniq
      LOGGING.debug "kubectl get privileged_containers: #{resp}"
      resp
    end

    def self.nodes : JSON::Any
      # TODO should this be all namespaces?
      resp = `kubectl get nodes -o json`
      LOGGING.debug "kubectl get nodes: #{resp}"
      JSON.parse(resp)
    end

    def self.deployment(deployment_name) : JSON::Any
      resp = `kubectl get deployment #{deployment_name} -o json`
      LOGGING.debug "kubectl get deployment: #{resp}"
      if resp && !resp.empty?
        JSON.parse(resp)
      else
        JSON.parse(%({}))
      end
    end

    def self.resource(kind, resource_name) : JSON::Any
      LOGGING.debug "kubectl get kind: #{kind} resource name: #{resource_name}"
      resp = `kubectl get #{kind} #{resource_name} -o json`
      LOGGING.debug "kubectl get resource: #{resp}"
      if resp && !resp.empty?
        JSON.parse(resp)
      else
        JSON.parse(%({}))
      end
    end

    def self.save_manifest(deployment_name, output_file) 
      resp = `kubectl get deployment #{deployment_name} -o yaml  > #{output_file}`
      LOGGING.debug "kubectl save_manifest: #{resp}"
      $?.success?
    end

    def self.deployments : JSON::Any
      resp = `kubectl get deployments -o json`
      LOGGING.debug "kubectl get deployment: #{resp}"
      if resp && !resp.empty?
        JSON.parse(resp)
      else
        JSON.parse(%({}))
      end
    end

    def self.deployment_containers(deployment_name) : JSON::Any 
      resource_containers("deployment", deployment_name)
    end

    def self.resource_containers(kind, resource_name) : JSON::Any 
      LOGGING.debug "kubectl get resource containers kind: #{kind} resource_name: #{resource_name}"
      unless kind.downcase == "service" ## services have no containers
        resp = resource(kind, resource_name).dig?("spec", "template", "spec", "containers")
      end
      LOGGING.debug "kubectl get resource containers: #{resp}"
      if resp && resp.as_a.size > 0
        resp
      else
        JSON.parse(%([]))
      end
    end

    def self.resource_volumes(kind, resource_name) : JSON::Any 
      LOGGING.debug "kubectl get resource volumes kind: #{kind} resource_name: #{resource_name}"
      unless kind.downcase == "service" ## services have no volumes
        resp = resource(kind, resource_name).dig?("spec", "template", "spec", "volumes")
      end
      LOGGING.debug "kubectl get resource volumes: #{resp}"
      if resp && resp.as_a.size > 0
        resp
      else
        JSON.parse(%([]))
      end
    end

    def self.secrets : JSON::Any
      resp = `kubectl get secrets -o json`
      LOGGING.debug "kubectl get secrets: #{resp}"
      if resp && !resp.empty?
        JSON.parse(resp)
      else
        JSON.parse(%({}))
      end
    end

    def self.configmaps : JSON::Any
      resp = `kubectl get configmaps -o json`
      LOGGING.debug "kubectl get configmaps: #{resp}"
      if resp && !resp.empty?
        JSON.parse(resp)
      else
        JSON.parse(%({}))
      end
    end

    def self.wait_for_install(deployment_name, wait_count : Int32 = 180, namespace="default")
      resource_wait_for_install("deployment", deployment_name, wait_count, namespace)
    end

    def self.resource_wait_for_install(kind : String, resource_name : String, wait_count : Int32 = 180, namespace="default")
      # Not all cnfs have #{kind}.  some have only a pod.  need to check if the 
      # passed in pod has a deployment, if so, watch the deployment.  Otherwise watch the pod 
      LOGGING.info "resource_wait_for_install kind: #{kind} resource_name: #{resource_name} namespace: #{namespace}"
      second_count = 0
      all_kind = `kubectl get #{kind} --namespace=#{namespace}`
      LOGGING.debug "all_kind #{all_kind}}"
      # TODO make this work for pods
      case kind.downcase
      when "replicaset", "deployment", "statefulset"
        desired_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.replicas}'`
        LOGGING.debug "desired_replicas #{desired_replicas}"
        current_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.readyReplicas}'`
        LOGGING.debug "current_replicas #{current_replicas}"
      when "daemonset"
        desired_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.desiredNumberScheduled}'`
        LOGGING.debug "desired_replicas #{desired_replicas}"
        current_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.numberAvailable}'`
        LOGGING.debug "current_replicas #{current_replicas}"
      else
        desired_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.replicas}'`
        LOGGING.debug "desired_replicas #{desired_replicas}"
        current_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.readyReplicas}'`
        LOGGING.debug "current_replicas #{current_replicas}"
      end

      until (current_replicas.empty? != true && current_replicas.to_i == desired_replicas.to_i) || second_count > wait_count
        LOGGING.info("second_count = #{second_count}")
        sleep 1
        LOGGING.debug "wait command: kubectl get #{kind} --namespace=#{namespace}"
        all_kind = `kubectl get #{kind} --namespace=#{namespace}`
        case kind.downcase
        when "replicaset", "deployment", "statefulset"
          current_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.readyReplicas}'`
          desired_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.replicas}'`
        when "daemonset"
          current_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.numberAvailable}'`
          desired_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.desiredNumberScheduled}'`
        else
          current_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.readyReplicas}'`
          desired_replicas = `kubectl get #{kind} --namespace=#{namespace} #{resource_name} -o=jsonpath='{.status.replicas}'`
        end
        LOGGING.debug "desired_replicas: #{desired_replicas}"
        LOGGING.info(all_kind)
        second_count = second_count + 1 
      end

      if (current_replicas.empty? != true && current_replicas.to_i == desired_replicas.to_i)
        true
      else
        false
      end
    end

    #TODO make dockercluser reference generic
    def self.wait_for_install_by_apply(manifest_file, wait_count=180)
      LOGGING.info "wait_for_install_by_apply"
      second_count = 0
      apply_resp = `kubectl apply -f #{manifest_file}`
      LOGGING.info("apply response: #{apply_resp}")
      until (apply_resp =~ /dockercluster.infrastructure.cluster.x-k8s.io\/capd unchanged/) != nil && (apply_resp =~ /cluster.cluster.x-k8s.io\/capd unchanged/) != nil && (apply_resp =~ /kubeadmcontrolplane.controlplane.cluster.x-k8s.io\/capd-control-plane unchanged/) != nil && (apply_resp =~ /kubeadmconfigtemplate.bootstrap.cluster.x-k8s.io\/capd-md-0 unchanged/) !=nil && (apply_resp =~ /machinedeployment.cluster.x-k8s.io\/capd-md-0 unchanged/) != nil && (apply_resp =~ /machinehealthcheck.cluster.x-k8s.io\/capd-mhc-0 unchanged/) != nil || second_count > wait_count.to_i
        LOGGING.info("second_count = #{second_count}")
        sleep 1
        apply_resp = `kubectl apply -f #{manifest_file}`
        LOGGING.info("apply response: #{apply_resp}")
        second_count = second_count + 1 
      end
    end 

    def self.resource_desired_is_available?(kind : String, resource_name)
      resp = `kubectl get #{kind} #{resource_name} -o=yaml`
      replicas_applicable = false
      case kind.downcase
      when "deployment", "statefulset", "replicaset" 
        replicas_applicable = true
        describe = Totem.from_yaml(resp)
        LOGGING.info("desired_is_available describe: #{describe.inspect}")
        desired_replicas = describe.get("status").as_h["replicas"].as_i
        LOGGING.info("desired_is_available desired_replicas: #{desired_replicas}")
        ready_replicas = describe.get("status").as_h["readyReplicas"]?
        unless ready_replicas.nil?
          ready_replicas = ready_replicas.as_i
        else
          ready_replicas = 0
        end
        LOGGING.info("desired_is_available ready_replicas: #{ready_replicas}")
      else
        replicas_applicable = false 
      end
      if replicas_applicable
        desired_replicas == ready_replicas
      else
        true
      end
    end
    def self.desired_is_available?(deployment_name)
      resource_desired_is_available?("deployment", deployment_name)
    end

    def self.pod_status(pod_name_prefix, field_selector="", namespace="default")
      all_pods = `kubectl get pods #{field_selector} -o jsonpath='{.items[*].metadata.name},{.items[*].metadata.creationTimestamp}'`.split(",")

      LOGGING.info(all_pods)
      all_pod_names = all_pods[0].split(" ")
      time_stamps = all_pods[1].split(" ")
      pods_times = all_pod_names.map_with_index do |name, i|
        {:name => name, :time => time_stamps[i]}
      end
      LOGGING.info("pods_times: #{pods_times}")

      # puts "Name: #{all_pods[0]}"
      # puts "Time Stamp: #{all_pods[1]}"
      latest_pod_time = pods_times.reduce() do | acc, i |
        # if current i > acc
        LOGGING.info("ACC: #{acc}")
        LOGGING.info("I:#{i}")
        LOGGING.info("pod_name_prefix: #{pod_name_prefix}")
        if (acc[:name] =~ /#{pod_name_prefix}/).nil?
          acc = {:name => "not found", :time => "not_found"} 
        end
        if i[:name] =~ /#{pod_name_prefix}/
          acc = i
          if acc == ""
            existing_time = Time.parse!( "#{i[:time]} +00:00", "%Y-%m-%dT%H:%M:%SZ %z")
          else
            existing_time = Time.parse!( "#{acc[:time]} +00:00", "%Y-%m-%dT%H:%M:%SZ %z")
          end
          new_time = Time.parse!( "#{i[:time]} +00:00", "%Y-%m-%dT%H:%M:%SZ %z")
          if new_time <= existing_time
            acc = i
          else
            acc
          end
        else
          acc
        end
      end
      LOGGING.info("latest_pod_time: #{latest_pod_time}")

      pod = latest_pod_time[:name].not_nil!
      # pod = all_pod_names[time_stamps.index(latest_time).not_nil!]
      # pod = all_pods.select{ | x | x =~ /#{pod_name_prefix}/ }
      puts "Pods Found: #{pod}"
      status = `kubectl get pods #{pod} -o jsonpath='{.metadata.name},{.status.phase},{.status.containerStatuses[*].ready}'`
      status
    end

    def self.node_status(node_name)
      all_nodes = `kubectl get nodes -o jsonpath='{.items[*].metadata.name}'`
      LOGGING.info(all_nodes)
      status = `kubectl get nodes #{node_name} -o jsonpath='{.status.conditions[?(@.type == "Ready")].status}'`
      status
    end

    def self.deployment_spec_labels(deployment_name) : JSON::Any 
      resource_spec_labels("deployment", deployment_name)
    end
    def self.resource_spec_labels(kind, resource_name) : JSON::Any 
      LOGGING.debug "resource_labels kind: #{kind} resource_name: #{resource_name}"
      resp = resource(kind, resource_name).dig?("spec", "template", "metadata", "labels")
      LOGGING.debug "resource_labels: #{resp}"
      if resp
        resp
      else
        JSON.parse(%({}))
      end
    end

    def self.container_image_tags(deployment_containers) : Array(NamedTuple(image: String, 
                                                                            tag: String | Nil))
      image_tags = deployment_containers.as_a.map do |container|
        LOGGING.debug "container (should have image and tag): #{container}"
        {image: container.as_h["image"].as_s.split(":")[0],
         #TODO an image may not have a tag
         tag: container.as_h["image"].as_s.split(":")[1]?}
      end
      LOGGING.debug "image_tags: #{image_tags}"
      image_tags
    end

    def self.worker_nodes : Array(String)
      resp = `kubectl get nodes --selector='!node-role.kubernetes.io/master' -o 'go-template={{range .items}}{{$taints:=""}}{{range .spec.taints}}{{if eq .effect "NoSchedule"}}{{$taints = print $taints .key ","}}{{end}}{{end}}{{if not $taints}}{{.metadata.name}}{{ "\\n"}}{{end}}{{end}}'`
      LOGGING.debug "kubectl get nodes: #{resp}"
      resp.split("\n")
    end
    def self.schedulable_nodes : Array(String)
      resp = `kubectl get nodes -o 'go-template={{range .items}}{{$taints:=""}}{{range .spec.taints}}{{if eq .effect "NoSchedule"}}{{$taints = print $taints .key ","}}{{end}}{{end}}{{if not $taints}}{{.metadata.name}}{{ "\\n"}}{{end}}{{end}}'`
      LOGGING.debug "kubectl get nodes: #{resp}"
      resp.split("\n")
    end
    def self.pv : JSON::Any
      # TODO should this be all namespaces?
      resp = `kubectl get pv -o json`
      LOGGING.debug "kubectl get pv: #{resp}"
      JSON.parse(resp)
    end
    def self.pv_items_by_claim_name(claim_name)
      items = pv["items"].as_a.map do |x|
        begin
          if x["spec"]["claimRef"]["name"] == claim_name
            x
          else
            nil
          end
        rescue ex
          LOGGING.info ex.message 
          nil
        end
      end.compact
      LOGGING.debug "pv items : #{items}"
      items 
    end
    def self.container_runtime
      nodes["items"][0]["status"]["nodeInfo"]["containerRuntimeVersion"].as_s
    end
    def self.container_runtimes
      runtimes = nodes["items"].as_a.map do |x|
        x["status"]["nodeInfo"]["containerRuntimeVersion"].as_s
      end
      LOGGING.info "runtimes: #{runtimes}"
      runtimes.uniq
    end
    def self.pods(all_namespaces=true) : JSON::Any
      option = all_namespaces ? "--all-namespaces" : ""
      resp = `kubectl get pods #{option} -o json`
      LOGGING.debug "kubectl get pods: #{resp}"
      JSON.parse(resp)
    end

    # *pod_exists* returns true if a pod containing *pod_name* exists, regardless of status.
    # If *check_ready* is set to true, *pod_exists* validates that the pod exists and 
    # has a ready status of true
    def self.pod_exists?(pod_name, check_ready=false, all_namespaces=false) 
      LOGGING.debug "pod_exists? pod_name: #{pod_name}"
      exists = pods(all_namespaces)["items"].as_a.any? do |x|
        (name_comparison = x["metadata"]["name"].as_s? =~ /#{pod_name}/
        (x["metadata"]["name"].as_s? =~ /#{pod_name}/) || 
          (x["metadata"]["generateName"]? && x["metadata"]["generateName"].as_s? =~ /#{pod_name}/)) &&
        (check_ready && (x["status"]["conditions"].as_a.find{|x| x["type"].as_s? == "Ready"} && x["status"].as_s? == "True") || check_ready==false)
      end
      LOGGING.debug "pod exists: #{exists}"
      exists 
    end
    def self.all_pod_statuses
      statuses = pods["items"].as_a.map do |x|
        x["status"]
      end
      LOGGING.debug "pod statuses: #{statuses}"
      statuses
    end
    def self.all_pod_container_statuses
      statuses = all_pod_statuses.map do |x|
        x["containerStatuses"].as_a
      end
      # LOGGING.info "pod container statuses: #{statuses}"
      statuses
    end
    def self.all_container_repo_digests
      imageids = all_pod_container_statuses.reduce([] of String) do |acc, x|
        # acc << "hi"
        acc | x.map{|i| i["imageID"].as_s}
      end
      LOGGING.debug "pod container image ids: #{imageids}"
      imageids
    end
  end
end
