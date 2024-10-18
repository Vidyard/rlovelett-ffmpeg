require 'open3'
require 'shellwords'
require 'fileutils'
require 'securerandom'

FIXED_LOWER_TO_UPPER_RATIO = 16.0/9.0
FIXED_UPPER_TO_LOWER_RATIO = 9.0/16.0

module FFMPEG
  class Transcoder
    @@timeout = 30

    def self.timeout=(time)
      @@timeout = time
    end

    def self.timeout
      @@timeout
    end

    def requires_pre_encode
      # Stitches and trims with dynamic resolution require pre-encoding
      @movie.requires_pre_encode ||= @movie.paths.size > 1 || (@movie.has_dynamic_resolution && @transcoder_options[:permit_dynamic_resolution_pre_encode])
      return @movie.requires_pre_encode
    end

    def initialize(movie, output_file, options = EncodingOptions.new, transcoder_options = {}, transcoder_prefix_options = {})
      @movie = movie
      @output_file = output_file
      @transcoder_options = transcoder_options

      # If the movie has frames with varying resolutions, we need to pre-encode the movie for trims
      # This is because ffmpeg can't reliably handle inputs that contain frames with differing resolutions particularly for trimming with `filter_complex`
      @movie.check_frame_resolutions if @transcoder_options[:permit_dynamic_resolution_pre_encode]

      if requires_pre_encode
        @movie.paths.each do |path|
          # Make the interim path folder if it doesn't exist
          dirname = "/tmp/interim"
          unless File.directory?(dirname)
            FileUtils.mkdir_p(dirname)
          end

          interim_path = "/tmp/interim/#{File.basename(path, File.extname(path))}_#{SecureRandom.urlsafe_base64}.mp4"
          @movie.interim_paths << interim_path
        end
      else
        @movie.interim_paths << @movie.paths
      end

      if options.is_a?(String)
        prefix_options = convert_prefix_options_to_string(transcoder_prefix_options)
        @raw_options = "#{prefix_options} #{EncodingOptions.new.convert_inputs(@movie.interim_paths)} #{options}"
      elsif options.is_a?(EncodingOptions)
        @raw_options = options.merge(:inputs => @movie.interim_paths) unless options.include? :inputs
      elsif options.is_a?(Hash)
        @raw_options = EncodingOptions.new(options.merge(inputs: @movie.interim_paths, any_streams_contain_audio: @movie.any_streams_contain_audio?), transcoder_prefix_options)
      else
        raise ArgumentError, "Unknown options format '#{options.class}', should be either EncodingOptions, Hash or String."
      end

      @transcoder_prefix_options = transcoder_prefix_options
      @errors = []

      apply_transcoder_options
    end

    def run(&)
      transcode_movie(&)
      if @transcoder_options[:validate]
        validate_output_file(&)
        return encoded
      else
        return nil
      end
    end

    def encoding_succeeded?
      @errors << "no output file created" and return false unless File.exist?(@output_file)
      @errors << "encoded file is invalid" and return false unless encoded.valid?
      true
    end

    def encoded
      @encoded ||= Movie.new(@output_file)
    end

    private

    def pre_encode_if_necessary
      return unless requires_pre_encode

      # Set a minimum frame rate
      output_frame_rate = [@raw_options[:frame_rate] || @movie.frame_rate, 30].max
      output_frame_rate = 30 if output_frame_rate > 300

      # Add a subset of the full encode options
      pre_encode_options = @raw_options.is_a?(EncodingOptions) ? @raw_options.to_s_minimal : @raw_options

      max_width, max_height = calculate_interim_max_dimensions

      silent_audio_source = '-f lavfi aevalsrc=0'

      # Convert the individual videos into a common format
      @movie.unescaped_paths.each_with_index do |path, index|
        audio_map = determine_audio_for_pre_encode(path)

        # Only re-scale the video if there are multiple inputs. If a single input video contains dynamic resolution it can cause issues with the filter_complex filter
        complex_filter = ""
        if @movie.paths.size > 1
          complex_filter = "-filter_complex \"[0:v]scale=#{max_width}:#{max_height}:force_original_aspect_ratio=decrease,pad=#{max_width}:#{max_height}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1[Scaled]\" -map \"[Scaled]\" #{audio_map}"
        end

        command = "#{@movie.ffmpeg_command} -y -i #{Shellwords.escape(path)} -movflags faststart #{pre_encode_options} -r #{output_frame_rate} #{complex_filter} #{@movie.interim_paths[index]}"
        FFMPEG.logger.info("Running pre-encoding...\n#{command}\n")
        output = ""

        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          begin
            yield(0.0) if block_given?
            next_line = Proc.new do |line|
              fix_encoding(line)
              output << line
              # TODO: Update this to actually yield progress updates relative to the overall output
              # if line.include?("time=")
              #   if line =~ /time=(\d+):(\d+):(\d+.\d+)/ # ffmpeg 0.8 and above style
              #     time = ($1.to_i * 3600) + ($2.to_i * 60) + $3.to_f
              #   else # better make sure it wont blow up in case of unexpected output
              #     time = 0.0
              #   end
              #   progress = time / @movie.duration
              #   yield(progress) if block_given?
              # end
            end

            if @@timeout
              stderr.each_with_timeout(wait_thr.pid, @@timeout, 'size=', &next_line)
            else
              stderr.each('size=', &next_line)
            end

          rescue Timeout::Error
            FFMPEG.logger.error "Process hung...\n@command\n#{command}\nOutput\n#{output}\n"
            delete_files(@movie.interim_paths[index])
            raise Error, "Process hung. Full output: #{output}"
          rescue StandardException
            FFMPEG.logger.error "Process failed...\n@command\n#{command}\nOutput\n#{output}\n"
            delete_files(@movie.interim_paths[index])
            raise
          end
        end
      end
    end

    def determine_audio_for_pre_encode(path)
      local_movie = Movie.new(path)
      # If there's a local audio stream, use that
      return '-map "0:a"' if local_movie.audio_streams.any?
      # Otherwise, use a silent audio source
      # | aevalsrc=0 will generate a silent audio source
      # | -shortest will make sure that the output is the duration of the shortest input (meaning the real source input)
      return '-filter_complex "aevalsrc=0[a]" -shortest -map "[a]"' if @movie.any_streams_contain_audio?
      # Otherwise, don't include any audio
      return ''
    end

    def delete_files(destination)
      FileUtils.rm_rf(destination, secure: true) unless destination.nil?
    end

    def transcode_movie
      pre_encode_if_necessary
      # change output file to /tmp/interim/output.mp4 needs to be unique to every run
      # get file extension from original file - dont overwrite original file
      temp_output_file = "/tmp/interim/#{File.basename(@output_file, File.extname(@output_file))}_#{SecureRandom.urlsafe_base64}#{File.extname(@output_file)}"
      @command = "#{@movie.ffmpeg_command} -y #{@raw_options} #{Shellwords.escape(temp_output_file)}"

      FFMPEG.logger.info("Running transcoding...\n#{@command}\n")
      @output = ""

      Open3.popen3(@command) do |stdin, stdout, stderr, wait_thr|
        begin
          yield(0.0) if block_given?
          next_line = Proc.new do |line|
            fix_encoding(line)
            @output << line
            if line.include?("time=")
              if line =~ /time=(\d+):(\d+):(\d+.\d+)/ # ffmpeg 0.8 and above style
                time = ($1.to_i * 3600) + ($2.to_i * 60) + $3.to_f
              else # better make sure it wont blow up in case of unexpected output
                time = 0.0
              end
              progress = time / @movie.duration
              yield(progress) if block_given?
            end
          end

          if @@timeout
            stderr.each_with_timeout(wait_thr.pid, @@timeout, 'size=', &next_line)
          else
            stderr.each('size=', &next_line)
          end

        rescue Timeout::Error
          FFMPEG.logger.error "Process hung...\n@command\n#{@command}\nOutput\n#{@output}\n"
          raise Error, "Process hung. Full output: #{@output}"
        end
      end
      FileUtils.cp(temp_output_file, @output_file)
      FileUtils.rm_rf(temp_output_file, secure: true)
    end

    def validate_output_file(&block)
      if encoding_succeeded?
        yield(1.0) if block_given?
        FFMPEG.logger.info "Transcoding of #{@movie.paths.join(', ')} to #{@output_file} succeeded\n"
      else
        errors = "Errors: #{@errors.join(", ")}. "
        FFMPEG.logger.error "Failed encoding...\n#{@command}\n\n#{@output}\n#{errors}\n"
        raise Error, "Failed encoding. #{errors} Full output: #{@output}"
      end
    end

    def apply_transcoder_options
       # if true runs #validate_output_file
      @transcoder_options[:validate] = @transcoder_options.fetch(:validate) { true }

      return if @movie.calculated_aspect_ratio.nil?
      case @transcoder_options[:preserve_aspect_ratio].to_s
      when "width"
        preserve_width(@movie.calculated_aspect_ratio)
      when "height"
        preserve_height(@movie.calculated_aspect_ratio)
      when "fit"
        # need to take rotation into account to compare aspect ratios correctly
        input_aspect_ratio = if @movie.rotation && (@movie.rotation / 90).odd?
                               1 / @movie.calculated_aspect_ratio
                             else
                               @movie.calculated_aspect_ratio
                             end
        options_aspect_ratio = @raw_options.width.to_f / @raw_options.height.to_f

        if options_aspect_ratio > input_aspect_ratio
          preserve_height(input_aspect_ratio)
        else
          preserve_width(input_aspect_ratio)
        end
      end
    end

    def preserve_height(input_aspect_ratio)
      new_width = fix_dimension(@raw_options.height * input_aspect_ratio)
      @raw_options[:resolution] = "#{new_width}x#{@raw_options.height}"
    end

    def preserve_width(input_aspect_ratio)
      new_height = fix_dimension(@raw_options.width / input_aspect_ratio)
      @raw_options[:resolution] = "#{@raw_options.width}x#{new_height}"
    end

    def fix_dimension(n)
      n = n.ceil.even? ? n.ceil : n.floor
      n += 1 if n.odd? # needed if n ended up with no decimals in the first place
      return n
    end

    def fix_encoding(output)
      output[/test/]
    rescue ArgumentError
      output.force_encoding("ISO-8859-1")
    end

    def convert_prefix_options_to_string(transcoder_prefix_options)
      prefix_options = "#{transcoder_prefix_options.is_a?(String) ? transcoder_prefix_options : EncodingOptions.new(transcoder_prefix_options)}"
      prefix_options = "#{prefix_options} " if prefix_options.length > 0
      return prefix_options
    end

    def calculate_interim_max_dimensions
      # Get max width and max height of all inputs from each frame
      max_width, max_height = @movie.check_frame_resolutions

      converted_width = (max_height * FIXED_LOWER_TO_UPPER_RATIO).ceil()
      converted_height = (max_width * FIXED_UPPER_TO_LOWER_RATIO).ceil()

      # Convert to always be a 16:9 ratio
      # If the converted width will not be a decrease in resolution, upscale the width
      if converted_width >= max_width
        max_width = converted_width
      # Otherwise, upscale the height
      else
        max_height = converted_height
      end

      # Ensure dimensions are even for scaling + padding to not have rounding issues
      # Relating to CRT-1554
      # See https://trac.ffmpeg.org/ticket/1618
      max_width += 1 unless max_width.even?
      max_height += 1 unless max_height.even?

      return max_width, max_height
    end
  end
end
