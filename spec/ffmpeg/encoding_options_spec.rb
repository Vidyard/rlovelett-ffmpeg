require 'spec_helper.rb'

module FFMPEG
  describe EncodingOptions do
    describe "ffmpeg arguments conversion" do

      it "should order input and seek_time correctly" do
        command = EncodingOptions.new(:input => 'my_movie.mp4', :seek_time => 2500).to_s
        command.should eq('-ss 2500 -i my_movie.mp4')
      end

      it "should convert video codec" do
        EncodingOptions.new(video_codec: "libx264").to_s.should eq("-vcodec libx264")
      end

      it "should know the width from the resolution or be nil" do
        EncodingOptions.new(resolution: "320x240").width.should eq(320)
        EncodingOptions.new.width.should be_nil
      end

      it "should know the height from the resolution or be nil" do
        EncodingOptions.new(resolution: "320x240").height.should eq(240)
        EncodingOptions.new.height.should be_nil
      end

      it "should convert frame rate" do
        EncodingOptions.new(frame_rate: 29.9).to_s.should eq("-r 29.9")
      end

      it "should convert the resolution" do
        EncodingOptions.new(resolution: "640x480").to_s.should include("-s 640x480")
      end

      it "should add calculated aspect ratio" do
        EncodingOptions.new(resolution: "640x480").to_s.should include("-aspect 1.3333333")
        EncodingOptions.new(resolution: "640x360").to_s.should include("-aspect 1.7777777777777")
      end

      it "should use specified aspect ratio if given" do
        output = EncodingOptions.new(resolution: "640x480", aspect: 1.77777777777778).to_s
        output.should include("-s 640x480")
        output.should include("-aspect 1.77777777777778")
      end

      it "should convert video bitrate" do
        EncodingOptions.new(video_bitrate: "600k").to_s.should eq("-b:v 600k")
      end

      it "should use k unit for video bitrate" do
        EncodingOptions.new(video_bitrate: 600).to_s.should eq("-b:v 600k")
      end

      it "should convert audio codec" do
        EncodingOptions.new(audio_codec: "aac").to_s.should eq("-acodec aac")
      end

      it "should convert audio bitrate" do
        EncodingOptions.new(audio_bitrate: "128k").to_s.should eq("-b:a 128k")
      end

      it "should use k unit for audio bitrate" do
        EncodingOptions.new(audio_bitrate: 128).to_s.should eq("-b:a 128k")
      end

      it "should convert audio sample rate" do
        EncodingOptions.new(audio_sample_rate: 44100).to_s.should eq("-ar 44100")
      end

      it "should convert audio channels" do
        EncodingOptions.new(audio_channels: 2).to_s.should eq("-ac 2")
      end

      it "should convert maximum video bitrate" do
        EncodingOptions.new(video_max_bitrate: 600).to_s.should eq("-maxrate 600k")
      end

      it "should convert mininimum video bitrate" do
        EncodingOptions.new(video_min_bitrate: 600).to_s.should eq("-minrate 600k")
      end

      it "should convert video bitrate tolerance" do
        EncodingOptions.new(video_bitrate_tolerance: 100).to_s.should eq("-bt 100k")
      end

      it "should convert buffer size" do
        EncodingOptions.new(buffer_size: 2000).to_s.should eq("-bufsize 2000k")
      end

      it "should convert threads" do
        EncodingOptions.new(threads: 2).to_s.should eq("-threads 2")
      end

      it "should convert duration" do
        EncodingOptions.new(duration: 30).to_s.should eq("-t 30")
      end

      it "should convert keyframe interval" do
        EncodingOptions.new(keyframe_interval: 60).to_s.should eq("-g 60")
      end

      it "should convert video preset" do
        EncodingOptions.new(video_preset: "max").to_s.should eq("-vpre max")
      end

      it "should convert audio preset" do
        EncodingOptions.new(audio_preset: "max").to_s.should eq("-apre max")
      end

      it "should convert file preset" do
        EncodingOptions.new(file_preset: "max.ffpreset").to_s.should eq("-fpre max.ffpreset")
      end

      it "should specify seek time" do
        EncodingOptions.new(seek_time: 1).to_s.should eq("-ss 1")
      end

      it 'should specify screenshot parameters when using -vframes' do
        EncodingOptions.new(screenshot: true, vframes: 123).to_s.should eq('-vframes 123 -f image2 ')
      end

      it "should specify screenshot parameters" do
        EncodingOptions.new(screenshot: true).to_s.should eq("-vframes 1 -f image2")
      end

      it "should put the parameters in order of codecs, presets, others" do
        opts = Hash.new
        opts[:frame_rate] = 25
        opts[:video_codec] = "libx264"
        opts[:video_preset] = "normal"

        converted = EncodingOptions.new(opts).to_s
        converted.should eq("-vcodec libx264 -vpre normal -r 25")
      end

      it "correctly identifies the input parameter" do
        converted = EncodingOptions.new({ input: 'somefile.mp4', custom: '-pass 1 passlogfile bla-i-bla' }).to_s
        converted.should eq("-i somefile.mp4 -pass 1 passlogfile bla-i-bla")
      end

      it "should convert a lot of them simultaneously" do
        converted = EncodingOptions.new(video_codec: "libx264", audio_codec: "aac", video_bitrate: "1000k").to_s
        converted.should match(/-acodec aac/)
      end

      it "should ignore options with nil value" do
        EncodingOptions.new(video_codec: "libx264", frame_rate: nil).to_s.should eq("-vcodec libx264 ")
      end

      it "should convert x264 vprofile" do
        EncodingOptions.new(x264_vprofile: "high").to_s.should eq("-vprofile high")
      end

      it "should convert x264 preset" do
        EncodingOptions.new(x264_preset: "slow").to_s.should eq("-preset slow")
      end

      it "should specify input watermark file" do
        EncodingOptions.new(watermark: "watermark.png").to_s.should eq("-i watermark.png")
      end

      it "should specify watermark position at left top corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "LT", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        converted.should include "-filter_complex 'scale=640x480,overlay=x=10:y=10'"
      end

      it "should specify watermark position at right top corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "RT", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        converted.should include "-filter_complex 'scale=640x480,overlay=x=main_w-overlay_w-10:y=10'"
      end

      it "should specify watermark position at left bottom corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "LB", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        converted.should include "-filter_complex 'scale=640x480,overlay=x=10:y=main_h-overlay_h-10'"
      end

      it "should specify watermark position at left bottom corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "RB", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        converted.should include "overlay=x=main_w-overlay_w-10:y=main_h-overlay_h-10'"
      end
    end

    describe "ffmpeg prefix arguments conversion" do
      it "should combine prefix options with provided, custom only" do
        opts = Hash.new
        opts[:frame_rate] = 25
        opts[:video_codec] = "libx264"
        opts[:input] = "my_movie.mp4"
        opts[:video_preset] = "normal"
        prefix_opts = Hash.new
        prefix_opts[:custom] = "-vsync 0 -hwaccel cuda -hwaccel_output_format cuda"
        converted = EncodingOptions.new(opts, prefix_opts).to_s
        converted.should eq("-vsync 0 -hwaccel cuda -hwaccel_output_format cuda -i my_movie.mp4 -vcodec libx264 -vpre normal -r 25")
      end

      it "should combine prefix options with provided, custom and converted options" do
        opts = Hash.new
        opts[:frame_rate] = 25
        opts[:input] = "my_movie.mp4"
        prefix_opts = Hash.new
        prefix_opts[:custom] = "-vsync 0 -hwaccel cuda -hwaccel_output_format cuda"
        prefix_opts[:video_codec] = "libx265"
        prefix_opts[:video_preset] = "normal"
        converted = EncodingOptions.new(opts, prefix_opts).to_s
        converted.should eq("-vsync 0 -hwaccel cuda -hwaccel_output_format cuda -vcodec libx265 -vpre normal -i my_movie.mp4 -r 25")
      end
    end
  end
end
