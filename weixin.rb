
class Session
	attr_accessor :sid, :uin, :uuid, :device_id, :from_username, :skey
end

class WeixinConfig
	attr_accessor :login_url, :qr_url, :token_url, :init_url, :send_msg_url, :sync_url, :device_id

	def initialize(hash)
		hash.each do |key, value|
			self.instance_variable_set("@#{key}", value)
		end
	end
end
# Steps to send a weixin message via web wx
# 0. get uuid
# 1. get QR
# 2. Verify QR via mobile weixin client
# 3. get redirect uri when QR is verified. the redirect uri is called as "token url"
# 4. get uin and sid by accessing the token url
# 5. get skey by accessing webwxsync url
# 6. send message
# 7. use ping message to keep this client alive

class Weixin
	attr_accessor :session, :config

	def initialize(config)
		@config = config
		@session = Session.new
		@session.uuid = self.get_uuid # get uuid when initializing it

	end

	def get_qr_url
		return @config.qr_url % ( @session.uuid )
	end

	def get_token_url
		url = @config.token_url % ( @session.uuid )

		http = HTTPClient.new
		response = http.get_content(url)
		if response.match(/redirect_uri/)
		# sample response
		# window.code=200;
		# window.redirect_uri="https://wx.qq.com/cgi-bin/mmwebwx-bin/webwxnewloginpage?ticket=aa99024e-c8c7-1031-8006-50e54929056d&lang=zh_CN&scan=1377437526";
			response = response.gsub("\n","")
			response = response.split(";")[1];
			redirect_uri = response.split("=\"")[1][0..-2]
			puts "got token id: #{redirect_uri}"
			return redirect_uri
		else
			puts "token url is not ready"
			return nil
		end
	end


	def get_uuid
		http = HTTPClient.new
		url = @config.login_url
		pp url
		response = http.get_content(url)
		# sample response value: 
		# 			window.QRLogin.code = 200; window.QRLogin.uuid = "EzltHAvxHxwE6M";
		uuid_string = response.split(";")[1]
		uuid_encoded = uuid_string.split(" = ")[1]
		uuid = uuid_encoded[1..-2]
		return uuid
	end
	
	def get_session_info token_uri
		http = HTTPClient.new
		sid = nil
		uin = nil
		message = http.get(token_uri)
		new_cookies = message.http_header.get("Set-Cookie")
		new_cookies.each do |cookie|
			cookie_string = cookie[1]
			cookie_name = cookie_string.split(";")[0]
			cookie_key = cookie_name.split("=")[0]
			cookie_value = cookie_name.split("=")[1]
			if cookie_key == "wxuin"
				uin = cookie_value
			elsif cookie_key == "wxsid"
				sid = cookie_value
			end
		end
	
		return sid, uin
	
	end
	
	def get_user_info
		http = HTTPClient.new
		uri = @config.init_url
	
		data = {
			"BaseRequest" => {
				:DeviceID 	=> 'e538770852445779',
				:Sid		=> @session.sid,
				:Skey		=> "",
				:Uin  		=> @session.uin,
			}
		}
	
		return http.post_content(uri, data.to_json)
	end
	
	def get_skey
		http = HTTPClient.new
		uri = @config.sync_url % (URI::encode(@session.sid))
	
		data = {
			"BaseRequest" => {
				:Sid		=> @session.sid,
				:Uin  		=> @session.uin,
				}, 
				"SyncKey" => {
					:Count => 0,
					:List => []
				}
			}
	
			content = http.post_content(uri, data.to_json)
			pp content
			response = JSON.parse(content)
			skey = response["SKey"]
			return skey
	#	$this->post_contents('https://wx.qq.com/cgi-bin/mmwebwx-bin/webwxsync?sid=' . urlencode($this->sid), '{"BaseRequest":{"Uin":'.$this->Uin.',"Sid":"'.$this->sid.'"},"SyncKey":{"Count":0,"List":[]}}');
	end
	
	def ready_for_msg?

		if @session.skey != nil
			return true
		end

		puts "try to get token url"
		token_uri = self.get_token_url
		if token_uri
			# uri ready
			puts "QR is verified"
			sid,uin = get_session_info token_uri
			@session.sid = sid
			@session.uin = uin

			user_info = self.get_user_info
			@session.from_username = JSON.parse(user_info)["User"]["UserName"]

			skey = self.get_skey
			@session.skey = skey

			if @session.skey != nil
				return true
			end
		end

		return false
	end

	def send_message (to, msg)
		# always refresh skey before sending message
		@session.skey = self.get_skey

		http = HTTPClient.new
		uri = @config.send_msg_url % (URI::encode(@session.sid))
	
		clientMsgId = Time.now.strftime("%s%L")
	
		data = {
			"BaseRequest" => {
				:Sid		=> @session.sid,
				:Uin  		=> @session.uin,
				:Skey 		=> @session.skey,
				:DeviceID   => @session.device_id
				}, 
				"Msg" => {
					"FromUserName" => @session.from_username,
					"ToUserName" => to,
					"Type" => 1,
					"Content" => msg,
					"ClientMsgId" => clientMsgId,
					"LocalID" => clientMsgId
				}
			}
		
		pp http.post_content(uri, data.to_json)
	end
	
	def keep_alive
		http = HTTPClient.new
		uri = @config.sync_url % (URI::encode(@session.sid))
	
		data = {
			"BaseRequest" => {
				:Sid		=> @session.sid,
				:Uin  		=> @session.uin,
			}, 
			"SyncKey" => {
				:Count => 0,
				:List => []
			}
		}
	
		pp http.post_content(uri, data.to_json)	
	end
end	