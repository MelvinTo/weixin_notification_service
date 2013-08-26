require 'sinatra'
require 'httpclient'
require 'pp'
require 'json'
require 'open-uri'
require './weixin.rb'
require 'yaml'

set :server, 'webrick'


config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), 'config.yml'))

weixin_config = WeixinConfig.new(config["weixin"])

to_username = config["proxy"]["to_username"]

wx = Weixin.new(weixin_config)

get '/qr' do
	"<img src='#{wx.get_qr_url}'></img>"
end

get '/send/:msg' do
	if wx.ready_for_msg?
		wx.send_message(to_username, params[:msg])
	else
		puts "It is not ready for sending message, please verify the QR first: http://localhost:4566/qr"
	end	
end

# thread to check if session is ready for sending msg, if so, launch ping message to keep it alive
Thread.new {
	while true
		if wx.ready_for_msg?
			puts "sending keep alive message"
			wx.keep_alive
			sleep 300
		else
			puts "session is not ready for sending msg"
			sleep 5
		end
		
	end
}
