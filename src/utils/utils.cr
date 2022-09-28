require "totem"
require "colorize"
require "log"
require "file_utils"
require "../constants.cr"

def stdout_info(msg)
  puts msg
end

def stdout_success(msg)
  puts msg.colorize(:green)
end

def stdout_warning(msg)
  puts msg.colorize(:yellow)
end

def stdout_failure(msg)
  puts msg.colorize(:red)
end

def local_helm_path
  if File.exists?(Helm::BASE_CONFIG)
    config = Totem.from_file Helm::BASE_CONFIG
    if config[":helm_binary_path"]? && config[":helm_binary_path"].as_s?
      return config[":helm_binary_path"].as_s
    end
  end

  FileUtils.pwd + Helm::DEFAULT_LOCAL_BINARY_PATH
end