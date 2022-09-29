class BinaryReference 
	# CNF_DIR = "cnfs"
	@helm: String?

	def global_helm_installed?
		ghelm = helm_global_response
		global_helm_version = helm_v3_version(ghelm)
		if (global_helm_version)
		true
		else
		false
		end
	end

	def helm_global_response(verbose=false)
		Process.run("helm version", shell: true, output: stdout = IO::Memory.new, error: stderr = IO::Memory.new)
		stdout.to_s
	end

	def helm_v3_version(helm_response)
		# version.BuildInfo{Version:"v3.1.1", GitCommit:"afe70585407b420d0097d07b21c47dc511525ac8", GitTreeState:"clean", GoVersion:"go1.13.8"}
		helm_v3 = helm_response.match /BuildInfo{Version:\"(v([0-9]{1,3}[\.]){1,2}[0-9]{1,3}).+"/
		helm_v3 && helm_v3.not_nil![1]
	end

	def global_helm
		"helm"
	end
	
	def local_helm
		local_helm_full_path
	end

	# Get helm directory
	def helm
		@helm ||= global_helm_installed? ? global_helm : local_helm
	end
end