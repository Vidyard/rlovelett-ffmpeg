require 'shellwords'

module FFMPEG
  class EncodingOptions < Hash
    include HardwareAcceleration

    def initialize(options = {}, prefix_options = {})
      @prefix_options = prefix_options
      # If we are not told otherwise, assume that at least one stream contains audio
      @any_streams_contain_audio = options.fetch(:any_streams_contain_audio, true)
      @use_gpu_acceleration = options.fetch(:use_gpu_acceleration, false) && options.fetch(:video_codec, '') == "h264_nvenc" && hardware_supports_gpu_hw_acceleration? && ffmpeg_supports_gpu_hw_acceleration?
      merge!(options)
    end

    # Returns the full subset of options any time a string is requested
    def to_s
      params = collect do |key, value|
        attempt_self_call(key, value)
      end

      prefix_params = @prefix_options&.map do |key, value|
        attempt_self_call(key, value)
      end

      # codecs should go before the presets so that the files will be matched successfully
      # all other parameters go after so that we can override whatever is in the preset
      inputs                    = params.select { |p| p =~ /(^\-i| \-i) / }
      seek                      = params.select {|p| p =~ /\-ss/ }
      codecs                    = params.select { |p| p =~ /codec/ }
      presets                   = params.select { |p| p =~ /\-.pre/ }
      contains_complex_filter   = params.any? { |p| p =~ /\-filter_complex / }

      other   = params - codecs - presets - inputs - seek
      params  = prefix_params + seek + inputs + codecs + presets + other

      num_inputs = inputs.first&.scan(/(^\-i| \-i) /)&.count || 0
      if num_inputs > 1 && !contains_complex_filter
        multi_input_output_filter = "-filter_complex \"#{default_multi_input_complex_filter(num_inputs)}\" -map \"[v]\""
        multi_input_output_filter += " -map \"[a]\"" if @any_streams_contain_audio
        params.push(multi_input_output_filter)
      end

      params_string = params.join(" ")
      params_string << " #{convert_aspect(calculate_aspect)}" if calculate_aspect?

      params_string
    end

    # Returns a subset of the full encoding options, and must be requested explicitly
    # Specifically useful for the pre-encode step which does not want the complex filters
    def to_s_minimal
      params = collect do |key, value|
        attempt_self_call(key, value)
      end

      # codecs should go before the presets so that the files will be matched successfully
      # all other parameters go after so that we can override whatever is in the preset
      inputs                    = params.select { |p| p =~ /\-i / }
      seek                      = params.select {|p| p =~ /\-ss/ }
      codecs                    = params.select { |p| p =~ /codec/ }
      presets                   = params.select { |p| p =~ /\-.pre/ }
      complex_filter            = params.select { |p| p =~ /\-filter_complex / }

      other   = params - codecs - presets - inputs - seek - complex_filter
      params  = codecs + presets + other

      params_string = params.join(" ")
      params_string << " #{convert_aspect(calculate_aspect)}" if calculate_aspect?

      params_string
    end

    def default_multi_input_complex_filter(num_inputs)
      input_forming = ''
      final_grouping = ''

      num_inputs.times do |index|
        input_forming += "[#{index}:v]setpts=PTS-STARTPTS[v#{index}];"
        # TODO support audio-less videos by checking if any streams exist
        final_grouping += "[v#{index}]"
        final_grouping += "[#{index}:a]" if @any_streams_contain_audio
      end

      final_grouping += "concat=n=#{num_inputs}:v=1:a=#{@any_streams_contain_audio ? 1 : 0}[v]"
      final_grouping += "[a]" if @any_streams_contain_audio
      return "#{input_forming}#{final_grouping}"
    end

    def width
      self[:resolution].split("x").first.to_i rescue nil
    end

    def height
      self[:resolution].split("x").last.to_i rescue nil
    end

    def attempt_self_call(key, value)
      if value
        if supports_option_public?(key)
          public_send("convert_#{key}", value)
        elsif supports_option_private?(key)
          send("convert_#{key}", value)
        end
      end
    end

    def convert_inputs(values)
      "-i #{values.join(' -i ')}"
    end

    private
    def supports_option_public?(option)
      # rubocop:disable Lint/SymbolConversion
      option = RUBY_VERSION < "1.9" ? "convert_#{option}" : "convert_#{option}".to_sym
      # rubocop:enable Lint/SymbolConversion
      public_methods.include?(option)
    end

    def supports_option_private?(option)
      # rubocop:disable Lint/SymbolConversion
      option = RUBY_VERSION < "1.9" ? "convert_#{option}" : "convert_#{option}".to_sym
      # rubocop:enable Lint/SymbolConversion
      private_methods.include?(option)
    end

    def convert_aspect(value)
      "-aspect #{value}"
    end

    def calculate_aspect
      width, height = self[:resolution].split("x")
      width.to_f / height.to_f
    end

    def calculate_aspect?
      self[:aspect].nil? && self[:resolution]
    end

    def convert_video_codec(value)
      "-vcodec #{value}"
    end

    def convert_frame_rate(value)
      "-r #{value}"
    end

    def convert_resolution(value)
      if @use_gpu_acceleration
        vars = value.split("x")
        "-vf scale_npp=#{vars[0].to_i}:#{vars[1].to_i}:format=yuv420p"
      else
        "-s #{value}"
      end
    end

    def convert_video_bitrate(value)
      "-b:v #{k_format(value)}"
    end

    def convert_audio_codec(value)
      "-acodec #{value}"
    end

    def convert_audio_bitrate(value)
      "-b:a #{k_format(value)}"
    end

    def convert_audio_sample_rate(value)
      "-ar #{value}"
    end

    def convert_audio_channels(value)
      "-ac #{value}"
    end

    def convert_video_max_bitrate(value)
      "-maxrate #{k_format(value)}"
    end

    def convert_video_min_bitrate(value)
      "-minrate #{k_format(value)}"
    end

    def convert_buffer_size(value)
      "-bufsize #{k_format(value)}"
    end

    def convert_video_bitrate_tolerance(value)
      "-bt #{k_format(value)}"
    end

    def convert_threads(value)
      "-threads #{value}"
    end

    def convert_duration(value)
      "-t #{value}"
    end

    def convert_video_preset(value)
      "-vpre #{value}"
    end

    def convert_audio_preset(value)
      "-apre #{value}"
    end

    def convert_file_preset(value)
      "-fpre #{value}"
    end

    def convert_keyframe_interval(value)
      "-g #{value}"
    end

    def convert_seek_time(value)
      "-ss #{value}"
    end

    def convert_screenshot(value)
      value ? "-vframes #{self[:vframes] || 1} -f image2" : ""
    end

    def convert_x264_vprofile(value)
      "-vprofile #{value}"
    end

    def convert_x264_preset(value)
      "-preset #{value}"
    end

    def convert_watermark(value)
      "-i #{value}"
    end

    def convert_watermark_filter(value)
      case value[:position].to_s
      when "LT"
        "-filter_complex 'scale=#{self[:resolution]},overlay=x=#{value[:padding_x]}:y=#{value[:padding_y]}'"
      when "RT"
        "-filter_complex 'scale=#{self[:resolution]},overlay=x=main_w-overlay_w-#{value[:padding_x]}:y=#{value[:padding_y]}'"
      when "LB"
        "-filter_complex 'scale=#{self[:resolution]},overlay=x=#{value[:padding_x]}:y=main_h-overlay_h-#{value[:padding_y]}'"
      when "RB"
        "-filter_complex 'scale=#{self[:resolution]},overlay=x=main_w-overlay_w-#{value[:padding_x]}:y=main_h-overlay_h-#{value[:padding_y]}'"
      end
    end

    def convert_custom(value)
      value
    end

    # Deprecated, but accounting for "old" syntax
    def convert_input(value)
      convert_inputs([value])
    end

    def k_format(value)
      value.to_s.include?("k") ? value : "#{value}k"
    end
  end
end
