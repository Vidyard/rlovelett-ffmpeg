require 'spec_helper.rb'

module FFMPEG
  describe EncodingOptions do
    describe "ffmpeg arguments conversion" do

      it "should order input and seek_time correctly" do
        command = EncodingOptions.new(:input => 'my_movie.mp4', :seek_time => 2500).to_s
        expect(command).to eq('-ss 2500 -i my_movie.mp4')
      end

      it "should convert video codec" do
        expect(EncodingOptions.new(video_codec: "libx264").to_s).to eq("-vcodec libx264")
      end

      it "should know the width from the resolution or be nil" do
        expect(EncodingOptions.new(resolution: "320x240").width).to eq(320)
        expect(EncodingOptions.new.width).to be_nil
      end

      it "should know the height from the resolution or be nil" do
        expect(EncodingOptions.new(resolution: "320x240").height).to eq(240)
        expect(EncodingOptions.new.height).to be_nil
      end

      it "should convert frame rate" do
        expect(EncodingOptions.new(frame_rate: 29.9).to_s).to eq("-r 29.9")
      end

      it "should convert the resolution" do
        expect(EncodingOptions.new(resolution: "640x480").to_s).to include("-s 640x480")
      end

      it "should add calculated aspect ratio" do
        expect(EncodingOptions.new(resolution: "640x480").to_s).to include("-aspect 1.3333333")
        expect(EncodingOptions.new(resolution: "640x360").to_s).to include("-aspect 1.7777777777777")
      end

      it "should use specified aspect ratio if given" do
        output = EncodingOptions.new(resolution: "640x480", aspect: 1.77777777777778).to_s
        expect(output).to include("-s 640x480")
        expect(output).to include("-aspect 1.77777777777778")
      end

      it "should convert video bitrate" do
        expect(EncodingOptions.new(video_bitrate: "600k").to_s).to eq("-b:v 600k")
      end

      it "should use k unit for video bitrate" do
        expect(EncodingOptions.new(video_bitrate: 600).to_s).to eq("-b:v 600k")
      end

      it "should convert audio codec" do
        expect(EncodingOptions.new(audio_codec: "aac").to_s).to eq("-acodec aac")
      end

      it "should convert audio bitrate" do
        expect(EncodingOptions.new(audio_bitrate: "128k").to_s).to eq("-b:a 128k")
      end

      it "should use k unit for audio bitrate" do
        expect(EncodingOptions.new(audio_bitrate: 128).to_s).to eq("-b:a 128k")
      end

      it "should convert audio sample rate" do
        expect(EncodingOptions.new(audio_sample_rate: 44100).to_s).to eq("-ar 44100")
      end

      it "should convert audio channels" do
        expect(EncodingOptions.new(audio_channels: 2).to_s).to eq("-ac 2")
      end

      it "should convert maximum video bitrate" do
        expect(EncodingOptions.new(video_max_bitrate: 600).to_s).to eq("-maxrate 600k")
      end

      it "should convert mininimum video bitrate" do
        expect(EncodingOptions.new(video_min_bitrate: 600).to_s).to eq("-minrate 600k")
      end

      it "should convert video bitrate tolerance" do
        expect(EncodingOptions.new(video_bitrate_tolerance: 100).to_s).to eq("-bt 100k")
      end

      it "should convert buffer size" do
        expect(EncodingOptions.new(buffer_size: 2000).to_s).to eq("-bufsize 2000k")
      end

      it "should convert threads" do
        expect(EncodingOptions.new(threads: 2).to_s).to eq("-threads 2")
      end

      it "should convert duration" do
        expect(EncodingOptions.new(duration: 30).to_s).to eq("-t 30")
      end

      it "should convert keyframe interval" do
        expect(EncodingOptions.new(keyframe_interval: 60).to_s).to eq("-g 60")
      end

      it "should convert video preset" do
        expect(EncodingOptions.new(video_preset: "max").to_s).to eq("-vpre max")
      end

      it "should convert audio preset" do
        expect(EncodingOptions.new(audio_preset: "max").to_s).to eq("-apre max")
      end

      it "should convert file preset" do
        expect(EncodingOptions.new(file_preset: "max.ffpreset").to_s).to eq("-fpre max.ffpreset")
      end

      it "should specify seek time" do
        expect(EncodingOptions.new(seek_time: 1).to_s).to eq("-ss 1")
      end

      it 'should specify screenshot parameters when using -vframes' do
        expect(EncodingOptions.new(screenshot: true, vframes: 123).to_s).to eq('-vframes 123 -f image2 ')
      end

      it "should specify screenshot parameters" do
        expect(EncodingOptions.new(screenshot: true).to_s).to eq("-vframes 1 -f image2")
      end

      it "should put the parameters in order of codecs, presets, others" do
        opts = Hash.new
        opts[:frame_rate] = 25
        opts[:video_codec] = "libx264"
        opts[:video_preset] = "normal"

        converted = EncodingOptions.new(opts).to_s
        expect(converted).to eq("-vcodec libx264 -vpre normal -r 25")
      end

      it "correctly identifies the input parameter" do
        converted = EncodingOptions.new({ input: 'somefile.mp4', custom: '-pass 1 passlogfile bla-i-bla' }).to_s
        expect(converted).to eq("-i somefile.mp4 -pass 1 passlogfile bla-i-bla")
      end

      it "correctly estimates the number of inputs if `-i` exists elsewhere for single input" do
        converted = EncodingOptions.new({ input: '/somefile/_d_nI-iSsSF9NkHEELjolg/input_7dbaa2c6c3eef5aecac7e5.mp4' }).to_s
        expect(converted).not_to include("-filter_complex")
      end

      it "correctly estimates the number of inputs if `-i` exists elsewhere for multiple inputs" do
        converted = EncodingOptions.new({ inputs: ['/somefile/_d_nI-iSsSF9NkHEELjolg/input_7dbaa2c6c3eef5aecac7e51.mp4', '/somefile/_d_nI-iSsSF9NkHEELjolg/input_7dbaa2c6c3eef5aecac7e52.mp4'] }).to_s
        expect(converted).to include("-filter_complex")
        expect(converted).to include("concat=n=2:v=1:a=1")
      end

      describe 'correctly detects multiple inputs if three provided' do
        it "without audio override" do
          converted = EncodingOptions.new({ inputs: ['somefile.mp4', 'someotherfile.mp4', 'someotherotherfile.mp4'] }).to_s
          expect(converted).to include("-filter_complex")
          expect(converted).to include("concat=n=3:v=1:a=1")
        end

        it "with audio override true" do
          converted = EncodingOptions.new({ inputs: ['somefile.mp4', 'someotherfile.mp4', 'someotherotherfile.mp4'], any_streams_contain_audio: true }).to_s
          expect(converted).to include("-filter_complex")
          expect(converted).to include("concat=n=3:v=1:a=1")
        end

        it "with audio override false" do
          converted = EncodingOptions.new({ inputs: ['somefile.mp4', 'someotherfile.mp4', 'someotherotherfile.mp4'], any_streams_contain_audio: false }).to_s
          expect(converted).to include("-filter_complex")
          expect(converted).to include("concat=n=3:v=1:a=0")
        end
    end

      it "should convert a lot of them simultaneously" do
        converted = EncodingOptions.new(video_codec: "libx264", audio_codec: "aac", video_bitrate: "1000k").to_s
        expect(converted).to match(/-acodec aac/)
      end

      it "should ignore options with nil value" do
        expect(EncodingOptions.new(video_codec: "libx264", frame_rate: nil).to_s).to eq("-vcodec libx264 ")
      end

      it "should convert x264 vprofile" do
        expect(EncodingOptions.new(x264_vprofile: "high").to_s).to eq("-vprofile high")
      end

      it "should convert x264 preset" do
        expect(EncodingOptions.new(x264_preset: "slow").to_s).to eq("-preset slow")
      end

      it "should specify input watermark file" do
        expect(EncodingOptions.new(watermark: "watermark.png").to_s).to eq("-i watermark.png")
      end

      it "should specify watermark position at left top corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "LT", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        expect(converted).to include "-filter_complex 'scale=640x480,overlay=x=10:y=10'"
      end

      it "should specify watermark position at right top corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "RT", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        expect(converted).to include "-filter_complex 'scale=640x480,overlay=x=main_w-overlay_w-10:y=10'"
      end

      it "should specify watermark position at left bottom corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "LB", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        expect(converted).to include "-filter_complex 'scale=640x480,overlay=x=10:y=main_h-overlay_h-10'"
      end

      it "should specify watermark position at left bottom corner" do
        opts = Hash.new
        opts[:resolution] = "640x480"
        opts[:watermark_filter] = { position: "RB", padding_x: 10, padding_y: 10 }
        converted = EncodingOptions.new(opts).to_s
        expect(converted).to include "overlay=x=main_w-overlay_w-10:y=main_h-overlay_h-10'"
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
        expect(converted).to eq("-vsync 0 -hwaccel cuda -hwaccel_output_format cuda -i my_movie.mp4 -vcodec libx264 -vpre normal -r 25")
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
        expect(converted).to eq("-vsync 0 -hwaccel cuda -hwaccel_output_format cuda -vcodec libx265 -vpre normal -i my_movie.mp4 -r 25")
      end
    end
  end
end
