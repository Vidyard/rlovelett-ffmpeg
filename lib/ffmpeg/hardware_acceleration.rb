module FFMPEG
  module HardwareAcceleration
    def hardware_supports_gpu_hw_acceleration?
      @hardware_supports_gpu_hw_acceleration ||= determine_if_hardware_gpu_acceleration
    end

    def ffmpeg_supports_gpu_hw_acceleration?
      @ffmpeg_supports_gpu_hw_acceleration ||= determine_if_ffmpeg_gpu_acceleration
    end

    def determine_if_hardware_gpu_acceleration
      command = "nvidia-smi -x -q | yq -M -p xml --xml-skip-proc-inst --xml-skip-directives '.nvidia_smi_log.attached_gpus'"
      spawn = POSIX::Spawn::Child.new(command)

      std_output_array = spawn.out&.split(/\n+/)

      return false if std_output_array.include?('command not found') || std_output_array.empty?

      return std_output_array[0].to_i.positive?
    end

    def determine_if_ffmpeg_gpu_acceleration
      command = "#{FFMPEG.ffmpeg_binary} -hide_banner -hwaccels"
      spawn = POSIX::Spawn::Child.new(command)

      std_output_array = spawn.out&.split(/\n+/)

      return true if std_output_array.include?('cuda')

      return false
    end
  end
end
