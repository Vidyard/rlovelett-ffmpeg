require 'spec_helper.rb'

module FFMPEG
  describe Transcoder do
    let(:movie) { Movie.new("#{fixture_path}/movies/awesome movie.mov") }
    let(:movie_with_two_inputs) { Movie.new(["#{fixture_path}/movies/awesome'movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"]) }
    let(:movie_with_three_inputs) { Movie.new(["#{fixture_path}/movies/awesome movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov", "#{fixture_path}/movies/awesome'movie.mov"]) }
    let(:movie_with_multiple_dimension_inputs) { Movie.new(["#{fixture_path}/movies/awesome_widescreen.mov", "#{fixture_path}/movies/sideways_movie.mov"]) }
    let(:movie_with_multiple_dimension_inputs_with_no_audio) { Movie.new(["#{fixture_path}/movies/test_automation_5s.mp4", "#{fixture_path}/movies/test_automation_5s.mp4"]) }
    let(:movie_with_multiple_dimension_inputs_with_partial_audio) { Movie.new(["#{fixture_path}/movies/test_automation_5s.mp4", "#{fixture_path}/movies/sideways_movie.mov"]) }

    describe "initialization" do
      let(:output_path) { "#{tmp_path}/awesome.flv" }

      it "should accept EncodingOptions as options" do
        expect { Transcoder.new(movie, output_path, EncodingOptions.new) }.not_to raise_error
      end

      it "should accept Hash as options" do
        expect { Transcoder.new(movie, output_path, video_codec: "libx264") }.not_to raise_error
      end

      it "should accept String as options" do
        expect { Transcoder.new(movie, output_path, "-vcodec libx264") }.not_to raise_error
      end

      it "should not accept anything else as options" do
        expect { Transcoder.new(movie, output_path, ["array?"]) }.to raise_error(ArgumentError, /Unknown options format/)
      end
    end

    describe "transcoding" do
      context 'with default transcoder_options' do
        before do
          expect(FFMPEG.logger).to receive(:info).at_least(:once)
        end

        context "when ffmpeg freezes" do
          before do
            @original_timeout = Transcoder.timeout
            @original_ffmpeg_binary = FFMPEG.ffmpeg_binary

            Transcoder.timeout = 1
            FFMPEG.ffmpeg_binary = "#{fixture_path}/bin/ffmpeg-hanging"
          end

          it "should fail when the timeout is exceeded" do
            expect(FFMPEG.logger).to receive(:error).at_least(:once)
            transcoder = Transcoder.new(movie, "#{tmp_path}/timeout.mp4")
            expect { transcoder.run }.to raise_error(FFMPEG::Error, /Process hung/)
          end

          after do
            Transcoder.timeout = @original_timeout
            FFMPEG.ffmpeg_binary = @original_ffmpeg_binary
          end
        end

        context "with timeout disabled" do
          before do
            @original_timeout = Transcoder.timeout
            Transcoder.timeout = false
          end

          it "should still work" do
            encoded = Transcoder.new(movie, "#{tmp_path}/awesome.mp4").run
            expect(encoded.resolution).to eq("640x480")
          end

          after { Transcoder.timeout = @original_timeout }
        end

        it "should transcode the movie with progress given an awesome movie" do
          FileUtils.rm_f "#{tmp_path}/awesome.flv"

          transcoder = Transcoder.new(movie, "#{tmp_path}/awesome.flv")
          progress_updates = []
          transcoder.run { |progress| progress_updates << progress }
          expect(transcoder.encoded).to be_valid
          expect(progress_updates).to include(0.0, 1.0)
          expect(progress_updates.length).to be >= 3
          expect(File.exist?("#{tmp_path}/awesome.flv")).to be_truthy
        end

        it "should transcode the movie with EncodingOptions" do
          FileUtils.rm_f "#{tmp_path}/optionalized.mp4"

          options = {video_codec: "libx264", frame_rate: 10, resolution: "320x240", video_bitrate: 300,
                     audio_codec: "aac", audio_bitrate: 32, audio_sample_rate: 22050, audio_channels: 1}

          encoded = Transcoder.new(movie, "#{tmp_path}/optionalized.mp4", options).run
          expect(encoded.video_bitrate).to be_within(90000).of(300000)
          expect(encoded.video_codec).to be =~ /h264/
          expect(encoded.resolution).to eq("320x240")
          expect(encoded.frame_rate).to eq(10.0)
          expect(encoded.audio_bitrate).to be_within(2000).of(32000)
          expect(encoded.audio_codec).to be =~ /aac/
          expect(encoded.audio_sample_rate).to eq(22050)
          expect(encoded.audio_channels).to eq(1)
        end

        context "with aspect ratio preservation" do
          before do
            @movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
            @options = {resolution: "320x240"}
          end

          it "should work on width" do
            special_options = {preserve_aspect_ratio: :width}

            encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
            expect(encoded.resolution).to eq("320x180")
          end

          it "should work on height" do
            special_options = {preserve_aspect_ratio: :height}

            encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
            expect(encoded.resolution).to eq("426x240")
          end

          it "should not be used if original resolution is undeterminable" do
            expect(@movie).to receive(:calculated_aspect_ratio).and_return(nil)
            special_options = {preserve_aspect_ratio: :height}

            encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
            expect(encoded.resolution).to eq("320x240")
          end

          it "should round to resolutions divisible by 2" do
            expect(@movie).to receive(:calculated_aspect_ratio).at_least(:once).and_return(1.234)
            special_options = {preserve_aspect_ratio: :width}

            encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
            expect(encoded.resolution).to eq("320x260") # 320 / 1.234 should at first be rounded to 259
          end

          context "fit" do
            before :each do
              @special_options = {preserve_aspect_ratio: :fit}
            end

            it "should preserve width when input is landscape and options resolution is portrait" do
              movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
              options = {resolution: "360x640"}

              encoded = Transcoder.new(movie, "#{tmp_path}/preserved_aspect.mp4", options, @special_options).run
              expect(encoded.resolution).to eq("360x202")
            end

            it "should preserve height when input is portrait and options resolution is landscape" do
              movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
              options = {resolution: "640x360"}

              encoded = Transcoder.new(movie, "#{tmp_path}/preserved_aspect.mp4", options, @special_options).run
              expect(encoded.resolution).to eq("270x360")
            end

            it "should preserve height when input is portrait and options resolution is a shorter portrait" do
              movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
              options = {resolution: "480x600"}

              encoded = Transcoder.new(movie, "#{tmp_path}/preserved_aspect.mp4", options, @special_options).run
              expect(encoded.resolution).to eq("450x600")
            end

            it "should preserve width when input is portrait and options resolution is a taller portrait" do
              movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
              options = {resolution: "360x640"}

              encoded = Transcoder.new(movie, "#{tmp_path}/preserved_aspect.mp4", options, @special_options).run
              expect(encoded.resolution).to eq("360x480")
            end

            it "should preserve width when input is landscape and options resolution is narrower landscape" do
              movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
              options = {resolution: "640x480"}

              encoded = Transcoder.new(movie, "#{tmp_path}/preserved_aspect.mp4", options, @special_options).run
              expect(encoded.resolution).to eq("640x360")
            end

            it "should preserve height when input is landscape and options resolution is wider landscape" do
              movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
              options = {resolution: "1280x360"}

              encoded = Transcoder.new(movie, "#{tmp_path}/preserved_aspect.mp4", options, @special_options).run
              expect(encoded.resolution).to eq("640x360")
            end
          end
        end

        it "should transcode the movie with String options" do
          FileUtils.rm_f "#{tmp_path}/string_optionalized.flv"

          encoded = Transcoder.new(movie, "#{tmp_path}/string_optionalized.flv", "-s 300x200 -ac 2").run
          expect(encoded.resolution).to eq("300x200")
          expect(encoded.audio_channels).to eq(2)
        end

        it "should transcode the movie which name include single quotation mark" do
          FileUtils.rm_f "#{tmp_path}/output.flv"

          movie = Movie.new("#{fixture_path}/movies/awesome'movie.mov")

          expect { Transcoder.new(movie, "#{tmp_path}/output.flv").run }.not_to raise_error
        end

        it "should transcode when output filename includes single quotation mark" do
          FileUtils.rm_f "#{tmp_path}/output with 'quote.flv"

          expect { Transcoder.new(movie, "#{tmp_path}/output with 'quote.flv").run }.not_to raise_error
        end

        pending "should not crash on ISO-8859-1 characters (dont know how to spec this)"

        it "should fail when given an invalid movie" do
          expect(FFMPEG.logger).to receive(:error).at_least(:once)
          movie = Movie.new(__FILE__)
          transcoder = Transcoder.new(movie, "#{tmp_path}/fail.flv")
          expect { transcoder.run }.to raise_error(FFMPEG::Error, /no output file created/)
        end

        it "should encode to the specified duration if given" do
          encoded = Transcoder.new(movie, "#{tmp_path}/durationalized.mp4", duration: 2).run

          expect(encoded.duration).to be >= 1.8
          expect(encoded.duration).to be <= 2.2
        end

        context 'multiple inputs' do
          after :each do
            FileUtils.rm_rf("#{fixture_path}/movies/interim/")
            FileUtils.rm_rf("#{tmp_path}/multi_input.mp4")
          end

          it "should encode with the duration matching the combined length when filter_complex is overridden" do
            advanced_encoding_options = "-filter_complex \"[0:v]scale,crop,transpose,setpts=PTS-STARTPTS[v0];[1:v]scale,crop,transpose,setpts=PTS-STARTPTS[v1];[v0][0:a][v1][1:a]concat=n=2:v=1:a=1[v][a]\" -map \"[v]\" -map \"[a]\""
            encoded = Transcoder.new(movie_with_two_inputs, "#{tmp_path}/multi_input.mp4", custom: advanced_encoding_options).run

            expect(encoded.duration).to be >= 14.4
            expect(encoded.duration).to be <= 15.2
          end

          it "should encode with the duration matching the combined length when filter_complex is not supplied with 2 videos" do
            encoded = Transcoder.new(movie_with_two_inputs, "#{tmp_path}/multi_input.mp4").run

            expect(encoded.duration).to be >= 14.4
            expect(encoded.duration).to be <= 15.2
          end

          it "should encode with the duration matching the combined length when filter_complex is not supplied with 3 videos" do
            encoded = Transcoder.new(movie_with_three_inputs, "#{tmp_path}/multi_input.mp4").run

            expect(encoded.duration).to be >= 21.6
            expect(encoded.duration).to be <= 22.7
          end
        end

        context "with screenshot option" do
          it "should transcode to original movies resolution by default" do
            encoded = Transcoder.new(movie, "#{tmp_path}/image.jpg", screenshot: true).run
            expect(encoded.resolution).to eq("640x480")
          end

          it "should transcode absolute resolution if specified" do
            encoded = Transcoder.new(movie, "#{tmp_path}/image.bmp", screenshot: true, seek_time: 3, resolution: '400x200').run
            expect(encoded.resolution).to eq("400x200")
          end

          it "should be able to preserve aspect ratio" do
            encoded = Transcoder.new(movie, "#{tmp_path}/image.png", {screenshot: true, seek_time: 4, resolution: '320x500'}, preserve_aspect_ratio: :width).run
            expect(encoded.resolution).to eq("320x240")
          end
        end

        context "audio only" do
          before do
            @original_timeout = Transcoder.timeout
            @original_ffmpeg_binary = FFMPEG.ffmpeg_binary

            Transcoder.timeout = 1
            FFMPEG.ffmpeg_binary = "#{fixture_path}/bin/ffmpeg-audio-only"
          end

          it "should not fail when the timeout is exceeded" do
            transcoder = Transcoder.new(movie, "#{tmp_path}/timeout.mp4")
            # Would expect to raise (FFMPEG::Error, /Process hung/) before this
            expect { transcoder.run }.to raise_error(FFMPEG::Error, /no output file created/)
          end

          after do
            Transcoder.timeout = @original_timeout
            FFMPEG.ffmpeg_binary = @original_ffmpeg_binary
          end
        end
      end
    end

    context "with :validate => false set as transcoding_options" do
      let(:transcoder) { Transcoder.new(movie, "tmp.mp4", {},{:validate => false}) }

      before(:each) do
        allow(transcoder).to receive(:transcode_movie)
      end
      after(:each) do
        FileUtils.rm_f "#{tmp_path}/tmp.mp4"
      end

      it "should not validate the movie output" do
        expect(transcoder).not_to receive(:validate_output_file)
        allow(transcoder).to receive(:encoded)
        transcoder.run
      end

      it "should not return Movie object" do
        allow(transcoder).to receive(:validate_output_file)
        expect(transcoder).not_to receive(:encoded)
        expect(transcoder.run).to eq(nil)
      end
    end

    describe "pre_encode_if_necessary" do
      let(:output_path) { "#{tmp_path}/pre_encode_out.mp4" }

      it 'returns early if only a single video file and no dynamic resolution' do
        transcoder = Transcoder.new(movie, output_path, EncodingOptions.new)
        allow(movie).to receive(:has_dynamic_resolution).and_return(false)
        expect(movie).not_to receive(:height)
        transcoder.send(:pre_encode_if_necessary)
      end

      it 'requires pre-encoding when movie has a single path and dynamic resolution is permitted' do
        transcoder = Transcoder.new(movie, output_path, EncodingOptions.new, { permit_dynamic_resolution_pre_encode: true })
        allow(movie).to receive(:has_dynamic_resolution).and_return(true)
        expect(transcoder.requires_pre_encode).to be true
      end

      it 'does not require pre-encoding when movie has a single path and dynamic resolution is not permitted' do
        transcoder = Transcoder.new(movie, output_path, EncodingOptions.new, { permit_dynamic_resolution_pre_encode: false })
        allow(movie).to receive(:has_dynamic_resolution).and_return(true)
        expect(transcoder.requires_pre_encode).to be false
      end

      describe 'creates interim inputs with scaling correctly applied based on input files' do
        it 'with audio' do
          transcoder = Transcoder.new(movie_with_multiple_dimension_inputs, output_path, EncodingOptions.new)
          allow(Open3).to receive(:popen3) do |*args|
            # Log the arguments passed to popen3
            puts "Open3.popen3 called with: #{args.join(' ')}\n"

            # Continue with the original behavior
            # Open3.popen3(*args)
          end
          expect(Open3).to receive(:popen3).exactly(2).times # prevent ffprobe calls from being evaluated (check_frame_resolutions)
          expect(Open3).to receive(:popen3).twice.with match(/.*\[0\:v\]scale\=854\:480.*pad\=854\:480\:\(ow\-iw\)\/2\:\(oh\-ih\)\/2\:color\=black.*\-map \"0\:a\".*/)

          transcoder.send(:pre_encode_if_necessary)
        end

        it 'with silent audio' do
          transcoder = Transcoder.new(movie_with_multiple_dimension_inputs_with_partial_audio, output_path, EncodingOptions.new)

          expect(Open3).to receive(:popen3).exactly(2).times # prevent ffprobe calls from being evaluated (check_frame_resolutions)
          # Match silent audio fill
          expect(Open3).to receive(:popen3).once.with match(/.*\[0\:v\]scale\=960\:540.*pad\=960\:540\:\(ow\-iw\)\/2\:\(oh\-ih\)\/2\:color\=black.*\-map \"\[a\]\".*/)
          # Retain "real" audio
          expect(Open3).to receive(:popen3).once.with match(/.*\[0\:v\]scale\=960\:540.*pad\=960\:540\:\(ow\-iw\)\/2\:\(oh\-ih\)\/2\:color\=black.*\-map \"0\:a\".*/)

          transcoder.send(:pre_encode_if_necessary)
        end

        it 'without any audio' do
          transcoder = Transcoder.new(movie_with_multiple_dimension_inputs_with_no_audio, output_path, EncodingOptions.new)

          expect(Open3).to receive(:popen3).exactly(2).times # prevent ffprobe calls from being evaluated (check_frame_resolutions)
          expect(Open3).to receive(:popen3).twice.with match(/.*\[0\:v\]scale\=960\:540.*pad\=960\:540\:\(ow\-iw\)\/2\:\(oh\-ih\)\/2\:color\=black.*((?!\-map \"0\:a\")(?!\-map \"\[a\]\")).*/)

          transcoder.send(:pre_encode_if_necessary)
        end
      end
    end

    describe "#requires_pre_encode" do
      let(:output_path) { "#{tmp_path}/output.mp4" }

      it 'requires pre-encoding when movie has multiple paths' do
        transcoder = Transcoder.new(movie_with_two_inputs, output_path, EncodingOptions.new)
        expect(transcoder.requires_pre_encode).to be true
      end

      it 'requires pre-encoding when movie has a single path and dynamic resolution is permitted' do
        movie = Movie.new("#{fixture_path}/movies/awesome movie.mov")
        transcoder_options = { permit_dynamic_resolution_pre_encode: true }
        transcoder = Transcoder.new(movie, output_path, EncodingOptions.new, transcoder_options)
        allow(movie).to receive(:has_dynamic_resolution).and_return(true)
        expect(transcoder.requires_pre_encode).to be true
      end

      it 'does not require pre-encoding when movie has a single path and dynamic resolution is not permitted' do
        movie = Movie.new("#{fixture_path}/movies/awesome movie.mov")
        transcoder_options = { permit_dynamic_resolution_pre_encode: false }
        transcoder = Transcoder.new(movie, output_path, EncodingOptions.new, transcoder_options)
        allow(movie).to receive(:has_dynamic_resolution).and_return(true)
        expect(transcoder.requires_pre_encode).to be false
      end

      it 'does not require pre-encoding when movie has a single path without dynamic resolution' do
        movie = Movie.new("#{fixture_path}/movies/awesome movie.mov")
        transcoder = Transcoder.new(movie, output_path, EncodingOptions.new)
        allow(movie).to receive(:has_dynamic_resolution).and_return(false)
        expect(transcoder.requires_pre_encode).to be false
      end
    end
  end
end
