require 'spec_helper.rb'

module FFMPEG # rubocop:todo Metrics/ModuleLength
  describe Movie do

    describe "initializing" do
      context "given a non existing file" do
        it "should throw ArgumentError" do
          expect { Movie.new("i_dont_exist") }.to raise_error(Errno::ENOENT, /does not exist/)
        end
      end

      context "given a non existing url" do
        it "should not be valid" do
          @movie = Movie.new("#{fixture_url_path}/movies/i_dont_exist")
          expect(@movie.valid?).to eq(false)
        end

        it "should contain error response 404" do
          @movie = Movie.new("#{fixture_url_path}/movies/i_dont_exist")
          expect(@movie.error).to eq("Server returned 404 Not Found")
        end
      end

      context "given a file containing a single quotation mark in the filename" do
        before(:all) do
          @movie = Movie.new("#{fixture_path}/movies/awesome'movie.mov")
        end

        it "should run ffmpeg successfully" do
          expect(@movie.duration).to be_within(0.01).of(7.56)
          expect(@movie.frame_rate).to be_within(0.01).of(16.75)
        end
      end

      context "given a valid file provided through an url" do
        before(:all) do
          @movie = Movie.new("#{fixture_url_path}/movies/awesome%20movie.mov?raw=true")
        end

        it "should run ffmpeg successfully" do
          expect(@movie.duration).to be_within(0.01).of(7.56)
          expect(@movie.frame_rate).to be_within(0.01).of(16.75)
          expect(@movie.error).to be(nil)
        end
      end

      context "given a non movie file" do
        before(:all) do
          @movie = Movie.new(__FILE__)
        end

        it "should not be valid" do
          expect(@movie).not_to be_valid
        end

        it "should have a duration of 0" do
          expect(@movie.duration).to eq(0)
        end

        it "should have nil height" do
          expect(@movie.height).to be_nil
        end

        it "should have nil width" do
          expect(@movie.width).to be_nil
        end

        it "should have nil frame_rate" do
          expect(@movie.frame_rate).to be_nil
        end

        it "should know the file size" do
          expect(File).to receive(:size).with(__FILE__).and_return(1)
          expect(@movie.size).to eq(1)
        end

        it 'should not be portrait' do
          expect(@movie.portrait?).not_to be_truthy
        end

        it 'should not be landscape' do
          expect(@movie.landscape?).not_to be_truthy
        end
      end

      context "given video with no duration" do
        it 'should not be zero duration' do
          ffprobe_fake_output = File.read("#{fixture_path}/outputs/file_missing_duration.txt")
          ffprobe_spawn_double = double(:out => ffprobe_fake_output, :err => '')
          expect(POSIX::Spawn::Child).to receive(:new).and_return(ffprobe_spawn_double)
          ffmpeg_fake_output = File.read("#{fixture_path}/outputs/file_null_encoded.txt")
          ffmpeg_spawn_double = double(:out => '', :err => ffmpeg_fake_output)
          expect(POSIX::Spawn::Child).to receive(:new).and_return(ffmpeg_spawn_double)
          @movie = Movie.new(__FILE__)

          expect(@movie.duration).to eq(222.65)
        end
      end

      context "given an empty flv file (could not find codec parameters)" do
        before(:all) do
          @movie = Movie.new("#{fixture_path}/movies/empty.flv")
        end

        it "should not be valid" do
          expect(@movie).not_to be_valid
        end

        it 'should not be portrait' do
          expect(@movie.portrait?).not_to be_truthy
        end

        it 'should not be landscape' do
          expect(@movie.landscape?).not_to be_truthy
        end
      end

      context "given a broken mp4 file" do
        before(:all) do
          @movie = Movie.new("#{fixture_path}/movies/broken.mp4")
        end

        it "should not be valid" do
          expect(@movie).not_to be_valid
        end

        it "should have nil calculated_aspect_ratio" do
          expect(@movie.calculated_aspect_ratio).to be_nil
        end

        it 'should not be portrait' do
          expect(@movie.portrait?).not_to be_truthy
        end

        it 'should not be landscape' do
          expect(@movie.landscape?).not_to be_truthy
        end
      end

      context "given a weird aspect ratio file" do
        before(:all) do
          @movie = Movie.new("#{fixture_path}/movies/weird_aspect.small.mpg")
        end

        it "should parse the DAR" do
          expect(@movie.dar).to eq("704:405")
        end

        it "should have correct calculated_aspect_ratio" do
          expect(@movie.calculated_aspect_ratio.to_s[0..14]).to eq("1.7382716049382") # substringed to be 1.9 compatible
        end
      end

      context "given an impossible DAR" do
        before(:each) do
          fake_output = File.read("#{fixture_path}/outputs/file_with_weird_dar.txt")
          spawn_double = double(:out => fake_output, :err => '')
          expect(POSIX::Spawn::Child).to receive(:new).and_return(spawn_double)
          @movie = Movie.new(__FILE__)
        end

        it "should parse the DAR" do
          expect(@movie.dar).to eq("0:1")
        end

        it "should calulate using width and height instead" do
          expect(@movie.calculated_aspect_ratio.to_s[0..14]).to eq("1.7777777777777") # substringed to be 1.9 compatible
        end
      end

      context "given a weird storage/pixel aspect ratio file" do
        before(:all) do
          @movie = Movie.new("#{fixture_path}/movies/weird_aspect.small.mpg")
        end

        it "should parse the SAR" do
          expect(@movie.sar).to eq("64:45")
        end

        it "should have correct calculated_pixel_aspect_ratio" do
          expect(@movie.calculated_pixel_aspect_ratio.to_s[0..14]).to eq("1.4222222222222") # substringed to be 1.9 compatible
        end
      end

      context "given an impossible SAR" do
        before(:each) do
          fake_output = File.read("#{fixture_path}/outputs/file_with_weird_sar.txt")
          spawn_double = double(:out => fake_output, :err => '')
          expect(POSIX::Spawn::Child).to receive(:new).and_return(spawn_double)
          @movie = Movie.new(__FILE__)
        end

        it "should parse the SAR" do
          expect(@movie.sar).to eq("0:1")
        end

        it "should using square SAR, 1.0 instead" do
          expect(@movie.calculated_pixel_aspect_ratio.to_s[0..14]).to eq("1") # substringed to be 1.9 compatible
        end
      end

      context "given a file with ISO-8859-1 characters in output" do
        it "should not crash" do
          fake_output = File.read("#{fixture_path}/outputs/file_with_iso-8859-1.txt")
          spawn_double = double(:out => fake_output, :err => '')
          expect(POSIX::Spawn::Child).to receive(:new).and_return(spawn_double)
          expect { Movie.new(__FILE__) }.to_not raise_error
        end
      end

      context "given a file with 5.1 audio" do
        before(:each) do
          fake_output = File.read("#{fixture_path}/outputs/file_with_surround_sound.txt")
          spawn_double = double(:out => fake_output, :err => '')
          expect(POSIX::Spawn::Child).to receive(:new).and_return(spawn_double)
          @movie = Movie.new(__FILE__)
        end

        it "should have 6 audio channels" do
          expect(@movie.audio_channels).to eq(6)
        end
      end

      context "given a file with no audio" do
        before(:each) do
          fake_output = File.read("#{fixture_path}/outputs/file_with_no_audio.txt")
          spawn_double = double(:out => fake_output, :err => '')
          expect(POSIX::Spawn::Child).to receive(:new).and_return(spawn_double)
          @movie = Movie.new(__FILE__)
        end

        it "should have nil audio channels" do
          expect(@movie.audio_channels).to eq(nil)
        end
      end

      context "given a file with non supported audio" do
        before(:each) do
          fake_stdout = File.read("#{fixture_path}/outputs/file_with_non_supported_audio_stdout.txt")
          fake_stderr = File.read("#{fixture_path}/outputs/file_with_non_supported_audio_stderr.txt")
          spawn_double = double(:out => fake_stdout, :err => fake_stderr)
          expect(POSIX::Spawn::Child).to receive(:new).and_return(spawn_double)
          @movie = Movie.new(__FILE__)
        end

        it "should be valid" do
          expect(@movie).to be_valid
        end
      end

      context "given an awesome movie file" do
        before(:all) do
          @movie = Movie.new("#{fixture_path}/movies/awesome movie.mov")
        end

        context "escaped paths" do
          it "should remember the movie path" do
            expect(@movie.path).to eq("#{fixture_path}/movies/awesome\\ movie.mov")
          end

          it "should return first path if multiple" do
            @movie = Movie.new(["#{fixture_path}/movies/awesome movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"])
            expect(@movie.path).to eq("#{fixture_path}/movies/awesome\\ movie.mov")
          end

          it "should return all paths if multiple" do
            @movie = Movie.new(["#{fixture_path}/movies/awesome movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"])
            expect(@movie.paths).to eq(["#{fixture_path}/movies/awesome\\ movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"])
          end
        end
        context "unescaped paths" do

          it "should remember the movie path" do
            expect(@movie.unescaped_path).to eq("#{fixture_path}/movies/awesome movie.mov")
          end

          it "should return first path if multiple" do
            @movie = Movie.new(["#{fixture_path}/movies/awesome movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"])
            expect(@movie.unescaped_path).to eq("#{fixture_path}/movies/awesome movie.mov")
          end

          it "should return all paths if multiple" do
            @movie = Movie.new(["#{fixture_path}/movies/awesome movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"])
            expect(@movie.unescaped_paths).to eq(["#{fixture_path}/movies/awesome movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"])
          end
        end

        it "should parse duration to number of seconds" do
          expect(@movie.duration).to be_within(0.01).of(7.56)
        end

        it "should parse the bitrate" do
          expect(@movie.bitrate).to be_between(481736, 481936)
        end

        it "should return nil rotation when no rotation exists" do
          expect(@movie.rotation).to eq(nil)
        end

        it "should parse the creation_time" do
          expect(@movie.creation_time).to eq(Time.parse("2010-02-05 16:05:04 UTC"))
        end

        it "should parse video stream information" do
          expect(@movie.video_stream).to eq("h264 (Main) (avc1 / 0x31637661), yuv420p, 640x480 [SAR 1:1 DAR 4:3]")
        end

        it "should know the video codec" do
          expect(@movie.video_codec).to be =~ /h264/
        end

        it "should know the colorspace" do
          expect(@movie.colorspace).to eq("yuv420p")
        end

        it "should know the resolution" do
          expect(@movie.resolution).to eq("640x480")
        end

        it "should know the video bitrate" do
          expect(@movie.video_bitrate).to eq(371185)
        end

        it "should know the video profile" do
          expect(@movie.video_profile).to eq("Main")
        end

        it "should know the video level" do
          expect(@movie.video_level).to eq(3.0)
        end

        it "should know the width and height" do
          expect(@movie.width).to eq(640)
          expect(@movie.height).to eq(480)
        end

        it "should know the framerate" do
          expect(@movie.frame_rate).to be_within(0.01).of(16.75)
        end

        it "should parse audio stream information" do
          expect(@movie.audio_stream).to eq("aac (mp4a / 0x6134706d), 44100 Hz, stereo, fltp, 75832 bit/s")
        end

        it "should know the audio codec" do
          expect(@movie.audio_codec).to be =~ /aac/
        end

        it "should know the sample rate" do
          expect(@movie.audio_sample_rate).to eq(44100)
        end

        it "should know the number of audio channels" do
          expect(@movie.audio_channels).to eq(2)
        end

        it "should know the audio bitrate" do
          expect(@movie.audio_bitrate).to eq(75832)
        end

        it "should should be valid" do
          expect(@movie).to be_valid
        end

        it "should calculate the aspect ratio" do
          expect(@movie.calculated_aspect_ratio.to_s[0..14]).to eq("1.3333333333333") # substringed to be 1.9 compatible
        end

        it "should know the file size" do
          expect(@movie.size).to eq(455546)
        end

        it "should know the container" do
          expect(@movie.container).to eq("mov,mp4,m4a,3gp,3g2,mj2")
        end
      end

      context "given a movie file with 2 audio streams" do
        let(:movie) { Movie.new("#{fixture_path}/movies/multi_audio_movie.mp4") }

        it "should identify both audio streams" do
          expect(movie.audio_streams.length).to eq(2)
        end

        it "should assign audio properties to the properties of the first stream" do
          audio_channels = movie.audio_streams[0][:channels]
          audio_codec = movie.audio_streams[0][:codec_name]
          audio_bitrate = movie.audio_streams[0][:bitrate]
          audio_channel_layout = movie.audio_streams[0][:channel_layout]
          audio_tags = movie.audio_streams[0][:tags]
          stream_overview = movie.audio_streams[0][:overview]

          expect(movie.audio_channels).to eq(audio_channels)
          expect(movie.audio_codec).to eq(audio_codec)
          expect(movie.audio_bitrate).to eq(audio_bitrate)
          expect(movie.audio_channel_layout).to eq(audio_channel_layout)
          expect(movie.audio_tags).to eq(audio_tags)
          expect(movie.audio_stream).to eq(stream_overview)
        end
      end
    end

    context 'given an awesome_widescreen file' do
      before(:all) do
        @movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
      end

      it 'should not be portrait' do
        expect(@movie.portrait?).not_to be_truthy
      end

      it 'should be landscape' do
        expect(@movie.landscape?).to be_truthy
      end
    end

    context 'given an sideways movie file' do
      before(:all) do
        @movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
      end

      it 'should not be landscape' do
        expect(@movie.portrait?).not_to be_truthy
      end

      it 'should be portrait' do
        expect(@movie.landscape?).to be_truthy
      end
    end

    context "given a rotated movie file" do
      before(:all) do
        @movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
      end

      it "should parse the rotation" do
        expect(@movie.rotation).to eq(-90)
      end
    end

    describe '#any_streams_contain_audio?' do
      it 'caches the result' do
        expect_any_instance_of(Movie).to receive(:calc_any_streams_contain_audio).once.and_return(true)
        movie = Movie.new("#{fixture_path}/movies/test_automation_5s.mp4")
        expect(movie.any_streams_contain_audio?).to be_truthy
        expect(movie.any_streams_contain_audio?).to be_truthy
      end

      it 'returns true if one stream contains audio' do
        movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
        expect(movie.any_streams_contain_audio?).to be_truthy
      end

      it 'returns true if any streams contain audio' do
        movie = Movie.new(["#{fixture_path}/movies/test_automation_5s.mp4", "#{fixture_path}/movies/awesome_widescreen.mov"])
        expect(movie.any_streams_contain_audio?).to be_truthy
      end

      it 'returns false if all stream contains no audio' do
        movie = Movie.new(["#{fixture_path}/movies/test_automation_5s.mp4", "#{fixture_path}/movies/test_automation_5s.mp4"])
        expect(movie.any_streams_contain_audio?).to be_falsey
      end

    end

    describe "transcode" do
      it "should run the transcoder for a single input" do
        movie = Movie.new("#{fixture_path}/movies/awesome movie.mov")

        transcoder_double = double(Transcoder)
        expect(Transcoder).to receive(:new).
          with(movie, "#{tmp_path}/awesome.flv", {custom: "-vcodec libx264"}, {preserve_aspect_ratio: :width}, {}).
          and_return(transcoder_double)
        expect(transcoder_double).to receive(:run)

        movie.transcode("#{tmp_path}/awesome.flv", {custom: "-vcodec libx264"}, {preserve_aspect_ratio: :width})
      end

      it "should run the transcoder for multiple inputs" do
        movie = Movie.new(["#{fixture_path}/movies/awesome movie.mov", "#{fixture_path}/movies/awesome_widescreen.mov"])

        transcoder_double = double(Transcoder)
        expect(Transcoder).to receive(:new).
          with(movie, "#{tmp_path}/awesome.flv", {custom: "-vcodec libx264"}, {preserve_aspect_ratio: :width}, {}).
          and_return(transcoder_double)
        expect(transcoder_double).to receive(:run)

        movie.transcode("#{tmp_path}/awesome.flv", {custom: "-vcodec libx264"}, {preserve_aspect_ratio: :width})
      end
    end

    describe 'ffprobe & ffmpeg command' do
      it 'returns the ffprobe command with default analyzeduration and probesize values' do
        allow(File).to receive(:exist?).and_return(true)
        movie = FFMPEG::Movie.new("")
        expect(movie.ffprobe_command).to eq("#{FFMPEG.ffprobe_binary} -hide_banner -analyzeduration 15000000 -probesize 15000000")
      end

      it 'returns the ffprobe command with custom analyzeduration and probesize values' do
        analyze_duration = 5000000
        probe_size = 1000000

        allow(File).to receive(:exist?).and_return(true)
        movie = FFMPEG::Movie.new("", analyzeduration = analyze_duration, probesize = probe_size)
        expect(movie.ffprobe_command).to eq("#{FFMPEG.ffprobe_binary} -hide_banner -analyzeduration #{analyzeduration} -probesize #{probesize}")
      end

      it 'returns the ffmpeg command with default analyzeduration and probesize values' do
        allow(File).to receive(:exist?).and_return(true)
        movie = FFMPEG::Movie.new("")
        expect(movie.ffmpeg_command).to eq("#{FFMPEG.ffmpeg_binary} -hide_banner -analyzeduration 15000000 -probesize 15000000")
      end

      it 'returns the ffmpeg command with custom analyzeduration and probesize values' do
        analyzeduration = 5000000
        probesize = 1000000

        allow(File).to receive(:exist?).and_return(true)
        movie = FFMPEG::Movie.new("", analyzeduration = analyzeduration, probesize = probesize)
        expect(movie.ffmpeg_command).to eq("#{FFMPEG.ffmpeg_binary} -hide_banner -analyzeduration #{analyzeduration} -probesize #{probesize}")
      end

      it 'allows getting the analyzeduration and probesize as an attr' do
        analyzeduration = 2000000
        probesize = 3000000

        allow(File).to receive(:exist?).and_return(true)
        movie = FFMPEG::Movie.new("", analyzeduration = analyzeduration, probesize = probesize)
        expect(movie.analyzeduration).to eq(analyzeduration)
        expect(movie.probesize).to eq(probesize)
      end
    end

    describe "screenshot" do
      it "should run the transcoder with screenshot option" do
        movie = Movie.new("#{fixture_path}/movies/awesome movie.mov")

        transcoder_double = double(Transcoder)
        expect(Transcoder).to receive(:new).
          with(movie, "#{tmp_path}/awesome.jpg", {seek_time: 2, dimensions: "640x480", screenshot: true}, {preserve_aspect_ratio: :width}, {}).
          and_return(transcoder_double)
        expect(transcoder_double).to receive(:run)

        movie.screenshot("#{tmp_path}/awesome.jpg", {seek_time: 2, dimensions: "640x480"}, {preserve_aspect_ratio: :width})
      end
    end

    describe "#check_frame_resolutions" do
      let(:movie) { Movie.new("#{fixture_path}/movies/awesome movie.mov") }
      let(:movie_with_multiple_dimension_inputs) { Movie.new(["#{fixture_path}/movies/awesome_widescreen.mov", "#{fixture_path}/movies/sideways_movie.mov"]) }

      it "handles empty frame resolution lines gracefully" do
        allow(Open3).to receive(:popen3).and_yield(nil, "640,480\n\n", nil, nil)
        expect(movie.check_frame_resolutions).to eq([640, 480, false])
      end

      describe 'returns the correct max width and height' do
        it "when resolutions are consistent" do
          allow(Open3).to receive(:popen3).and_yield(nil, "640,480\n640,480\n", nil, nil)
          expect(movie.check_frame_resolutions).to eq([640, 480, false])
        end

        it "when resolutions are inconsistent" do
          allow(Open3).to receive(:popen3).and_yield(nil, "640,480\n1920,300\n", nil, nil)
          expect(movie.check_frame_resolutions).to eq([1920, 480, true])
        end

        it "when multiple inputs are provided" do
          allow(Open3).to receive(:popen3).and_yield(nil, "640,480\n", nil, nil).and_yield(nil, "1920,300\n", nil, nil)
          expect(movie_with_multiple_dimension_inputs.check_frame_resolutions).to eq([1920, 480, true])
        end
      end
    end
  end
end
