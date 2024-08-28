require 'time'
require 'multi_json'
require 'posix-spawn'

module FFMPEG
  class Movie
    attr_reader :path, :paths, :unescaped_paths, :interim_paths, :duration, :time, :bitrate, :rotation, :creation_time, :analyzeduration, :probesize
    attr_reader :video_stream, :video_codec, :video_bitrate, :colorspace, :width, :height, :sar, :dar, :frame_rate, :has_b_frames, :video_profile, :video_level, :video_start_time
    attr_reader :audio_streams, :audio_stream, :audio_codec, :audio_bitrate, :audio_sample_rate, :audio_channels, :audio_tags, :audio_start_time
    attr_reader :color_primaries, :avframe_color_space, :color_transfer
    attr_reader :container
    attr_reader :error

    attr_accessor :has_dynamic_resolution, :requires_pre_encode

    UNSUPPORTED_CODEC_PATTERN = /^Unsupported codec with id (\d+) for input stream (\d+)$/

    def initialize(paths, analyzeduration = 15000000, probesize=15000000 )
      paths = [paths] unless paths.is_a? Array

      @unescaped_paths = paths
      inputs = []
      paths.each do |path|
        raise Errno::ENOENT, "the file '#{path}' does not exist" unless File.exist?(path) || path =~ URI::regexp(["http", "https"])
        inputs.push Shellwords.escape(path)
      end

      @paths = inputs
      @interim_paths = []
      @analyzeduration = analyzeduration;
      @probesize = probesize;

      if @paths.any? {|path| path.end_with?('.m3u8') }
        optional_arguments = '-allowed_extensions ALL'
      else
        optional_arguments = ''
      end

      # ffmpeg will output to stderr
      # This will only fetch the metadata for the first video provided
      command = "#{ffprobe_command} -hide_banner #{optional_arguments} -i #{@paths.first} -print_format json -show_format -show_streams -show_error -loglevel quiet"
      spawn = POSIX::Spawn::Child.new(command)

      std_output = spawn.out
      std_error = spawn.err

      fix_encoding(std_output)
      fix_encoding(std_error)

      begin
        metadata = MultiJson.load(std_output, symbolize_keys: true)
      rescue MultiJson::ParseError
        raise "Could not parse output from FFProbe:\n#{ std_output }\n#{ std_error }"
      end

      if metadata.key?(:error)
        @error = metadata[:error][:string]
        @duration = 0
      else
        video_streams = metadata[:streams].select { |stream| stream.key?(:codec_type) and stream[:codec_type] === 'video' }
        audio_streams = metadata[:streams].select { |stream| stream.key?(:codec_type) and stream[:codec_type] === 'audio' }

        @container = metadata[:format][:format_name]

        @duration = metadata[:format][:duration].to_f

        @time = metadata[:format][:start_time].to_f

        @creation_time = if metadata[:format].key?(:tags) and metadata[:format][:tags].key?(:creation_time)
                           Time.parse(metadata[:format][:tags][:creation_time])
                         else
                           nil
                         end

        @bitrate = metadata[:format][:bit_rate].to_i
        @size = metadata[:format][:size].to_i

        unless video_streams.empty?
          # TODO: Handle multiple video codecs (is that possible?)
          video_stream = video_streams.first
          @video_codec = video_stream[:codec_name]
          @colorspace = video_stream[:pix_fmt]
          @color_primaries = video_stream[:color_primaries]
          @avframe_color_space = video_stream[:color_space]
          @color_transfer = video_stream[:color_transfer]
          @width = video_stream[:width]
          @height = video_stream[:height]
          @video_bitrate = video_stream[:bit_rate].to_i
          @sar = video_stream[:sample_aspect_ratio]
          @dar = video_stream[:display_aspect_ratio]
          @has_b_frames = video_stream[:has_b_frames].to_i
          @video_profile = video_stream[:profile]
          @video_level = video_stream[:level] / 10.0 unless video_stream[:level].nil?
          @frame_rate = unless video_stream[:avg_frame_rate] == '0/0'
                          Rational(video_stream[:avg_frame_rate])
                        else
                          nil
                        end
          @video_start_time = video_stream[:start_time].to_f

          @video_stream = "#{video_stream[:codec_name]} (#{video_stream[:profile]}) (#{video_stream[:codec_tag_string]} / #{video_stream[:codec_tag]}), #{colorspace}, #{resolution} [SAR #{sar} DAR #{dar}]"

          video_stream[:side_data_list].each do |side_data_entry|
            @rotation = if side_data_entry.key?(:rotation)
                          side_data_entry[:rotation].to_i
                        else
                          nil
                        end
          end if video_stream.key?(:side_data_list)
        end

        @audio_streams = audio_streams.map do |stream|
          {
            :index => stream[:index],
            :channels => stream[:channels].to_i,
            :codec_name => stream[:codec_name],
            :sample_rate => stream[:sample_rate].to_i,
            :bitrate => stream[:bit_rate].to_i,
            :channel_layout => stream[:channel_layout],
            :tags => stream[:tags],
            :overview => "#{stream[:codec_name]} (#{stream[:codec_tag_string]} / #{stream[:codec_tag]}), #{stream[:sample_rate]} Hz, #{stream[:channel_layout]}, #{stream[:sample_fmt]}, #{stream[:bit_rate]} bit/s"
          }
        end

        audio_stream = @audio_streams.first
        unless audio_stream.nil?
          @audio_channels = audio_stream[:channels]
          @audio_codec = audio_stream[:codec_name]
          @audio_sample_rate = audio_stream[:sample_rate]
          @audio_bitrate = audio_stream[:bitrate]
          @audio_channel_layout = audio_stream[:channel_layout]
          @audio_tags = audio_stream[:tags]
          @audio_stream = audio_stream[:overview]
          @audio_start_time = audio_stream[:start_time].to_f
        end
      end

      @duration = manually_extract_duration if @duration.nil? || @duration.zero?

      unsupported_stream_ids = unsupported_streams(std_error)
      nil_or_unsupported = ->(stream) { stream.nil? || unsupported_stream_ids.include?(stream[:index]) }

      nil_or_unsupported_stream = nil_or_unsupported.(video_stream) && nil_or_unsupported.(audio_stream)
      metadata_error = metadata.key?(:error)
      std_err_codec_failure = std_error.include?("could not find codec parameters")
      FFMPEG.logger.error(std_error)
      if nil_or_unsupported_stream or metadata_error or std_err_codec_failure
        @invalid = true
        FFMPEG.logger.error(
          nil_or_unsupported_stream: nil_or_unsupported_stream,
          metadata_error: metadata_error,
          std_err_codec_failure: std_err_codec_failure,
          std_error: std_error
        )
      end
    end

    # Run null encoding output to get actual duration if none provided
    def manually_extract_duration
      command = "#{ffmpeg_command} -i #{@paths.first} -v quiet -stats -f null -"
      spawn = POSIX::Spawn::Child.new(command)

      # outputs to std error
      std_error = spawn.err
      fix_encoding(std_error)

      string_duration = std_error.scan(/time=(\d+:\d+:\d+\.\d+)/).last.first

      return string_duration.split(':').map(&:to_f).inject(0) { |a, b| (a * 60) + b }
    rescue Exception => e # rubocop:todo Lint/RescueException
      FFMPEG.logger.error("Failed to extract duration from #{@paths.first}")
      FFMPEG.logger.error(e)
      return 0
    end

    def ffprobe_command
      ff_command(FFMPEG.ffprobe_binary)
    end

    def ffmpeg_command
      ff_command(FFMPEG.ffmpeg_binary)
    end

    def ff_command(binary)
      "#{binary} -hide_banner -analyzeduration #{@analyzeduration} -probesize #{@probesize}"
    end

    def unsupported_streams(std_error)
      [].tap do |stream_indices|
        std_error.each_line do |line|
          match = line.match(UNSUPPORTED_CODEC_PATTERN)
          stream_indices << match[2].to_i if match
        end
      end
    end

    def valid?
      not @invalid
    end

    def resolution
      unless width.nil? or height.nil?
        "#{width}x#{height}"
      end
    end

    def calculated_aspect_ratio
      aspect_from_dar || aspect_from_dimensions
    end

    def calculated_pixel_aspect_ratio
      aspect_from_sar || 1
    end

    def size
      if @size
        @size
      else
        File.size(path)
      end
    end

    def audio_channel_layout
      # TODO Whenever support for ffmpeg/ffprobe 1.2.1 is dropped this is no longer needed
      @audio_channel_layout || case(audio_channels)
                                 when 1
                                   'stereo'
                                 when 2
                                   'stereo'
                                 when 6
                                   '5.1'
                                 else
                                   'unknown'
                               end
    end

    def path
      @paths.first
    end

    def unescaped_path
      @unescaped_paths.first
    end

    def portrait?
      width && height && (height > width)
    end

    def landscape?
      width && height && (width > height)
    end

    def transcode(output_file, options = EncodingOptions.new, transcoder_options = {}, transcoder_prefix_options = {}, &)
      puts "\n\nRlovelett-ffmpeg: Movie.transcode\n\n"
      Transcoder.new(self, output_file, options, transcoder_options, transcoder_prefix_options).run(&)
    end

    def screenshot(output_file, options = EncodingOptions.new, transcoder_options = {}, transcoder_prefix_options = {}, &)
      Transcoder.new(self, output_file, options.merge(screenshot: true), transcoder_options, transcoder_prefix_options).run(&)
    end

    def blackdetect
      BlackDetect.new(self).run
    end

    def any_streams_contain_audio?
      @any_streams_contain_audio ||= calc_any_streams_contain_audio
    end

    def check_frame_resolutions
      max_width = @movie.width
      max_height = @movie.height
      differing_frame_resolutions = false
      last_line = nil

      @movie.unescaped_paths.each do |path|
        local_movie = Movie.new(path) # reference from highest res frames

        command = "#{@movie.ffprobe_command} -v error -select_streams v:0 -show_entries frame=width,height -of csv=p=0 -skip_frame nokey #{Shellwords.escape(local_movie.path)}" # -skip_frame nokey speeds up processing significantly
        FFMPEG.logger.info("Running check for varying resolution...\n#{command}\n")

        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          stdout.each_line do |line|
            # Parse the width and height from the line
            width, height = line.split(',').map(&:to_i)

            # Update max width and max height
            max_width = [max_width, width].max
            max_height = [max_height, height].max

            # Check if the current frame resolution differs from the last frame
            if last_line && line != last_line
              differing_frame_resolutions = true
            end

            last_line = line
          end
        end
      end

      @has_dynamic_resolution = differing_frame_resolutions

      # Return the max width, max height, and whether differing resolutions were found
      [max_width, max_height, differing_frame_resolutions]
    end

    protected

    def calc_any_streams_contain_audio
      return true unless @audio_stream.nil? || @audio_stream.empty?
      @unescaped_paths.each do |path|
        local_movie = Movie.new(path)
        return true unless local_movie.audio_stream.nil? || local_movie.audio_stream.empty?
      end

      return false
    end

    def aspect_from_dar
      return nil unless dar
      w, h = dar.split(":")
      aspect = w.to_f / h.to_f
      aspect.zero? ? nil : aspect
    end

    def aspect_from_sar
      return nil unless sar
      w, h = sar.split(":")
      aspect = w.to_f / h.to_f
      aspect.zero? ? nil : aspect
    end

    def aspect_from_dimensions
      aspect = width.to_f / height.to_f
      aspect.nan? ? nil : aspect
    end

    def fix_encoding(output)
      output[/test/] # Running a regexp on the string throws error if it's not UTF-8
    rescue ArgumentError
      output.force_encoding("ISO-8859-1")
    end
  end
end
