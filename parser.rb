require "rubygems"

# Image managment
require "gruff"
require "gosu"
require "mini_magick"

# Parse message data
require "json"
require "date"
require 'active_support/core_ext/numeric/time'

# Interact with Instagram API
require "net/http"
require 'uri'
require "open-uri"

module IGParser
	# Instagram was released in 2010
	TWENTY_TEN = Date.new(2010, 1, 1).to_time

	$user_cache = Hash.new

	class MessageTotals
		attr_accessor :total, :participants, :sent, :received, :total_likes, :likes_given, :likes_received, :detailed_likes

		def initialize(participants)
			@participants = Array.new
			@total = @received = @total_likes = 0

			@likes_given, @likes_received = Hash.new, Hash.new
			@detailed_likes, @sent = Hash.new, Hash.new

			participants.each do |participant|
				add_participant(participant)
			end
		end

		def add_participant(participant)
			@participants << participant

			@likes_given[participant] = 0
			@likes_received[participant] = 0
			@sent[participant] = 0

			likes_hash = Hash.new

			@participants.each do |other_participant|
				likes_hash[other_participant] = 0
				if (other_participant != participant)
					@detailed_likes[other_participant][participant] = 0
				end
			end

			@detailed_likes[participant] = likes_hash
		end

		# Combine two seperate like totals from the same conversation
		def +(other)
			totals = MessageTotals.new(Array.new)

			totals.total = @total + other.total
			totals.received = @received + other.received
			totals.total_likes = @total_likes + other.total_likes

			# TODO: deduplication here

			@sent.each do |user|
				totals.sent[user] = @sent[user]
				if (other.sent.key?(user))
					totals.sent[user] += other.sent[user]
				end
			end

			@likes_given.each do |user|
				totals.likes_given[user] = @likes_given[user]
				if (other.likes_given.key?(user))
					totals.likes_given[user] += other.likes_given[user]
				end
			end

			@likes_received.each do |user|
				totals.likes_received[user] = @likes_received[user]
				if (other.likes_received.key?(user))
					totals.likes_received[user] += other.likes_received[user]
				end
			end

			@detailed_likes.each do |like_reciever, likes_hash|
				detailed_likes = Hash.new
				likes_hash.each do |like_giver|
					detailed_likes[like_giver] = @detailed_likes[like_reciever][like_giver]
					if (other.detailed_likes.key?(like_reciever) && other.detailed_likes[like_reciever].key?(like_giver))
						detailed_likes[like_giver] += other.detailed_likes[like_reciever][like_giver]
					end
				end
				totals.detailed_likes[like_reciever] = detailed_likes
			end

			return totals
		end
	end

	class User
		attr_reader :username, :name, :bio, :pfp, :followers, :following

		def initialize(username, name=nil, bio=nil, pfp=nil, followers=nil, following=nil)
			@username = username

			if (name)
				@name = name
				@bio = bio
				@pfp = pfp
				@followers = followers
				@following = following
				return
			end

			puts "Fetching profile for #{username}..."

			response = Net::HTTP.get(URI.parse("https://www.instagram.com/#{@username}/?__a=1"))

			info = nil

			begin
				info = JSON.parse(response)
			rescue
				@name, @bio = "Invalid User", "Invalid Bio"
				@followers = @following = 0
				return
			end

			if (info.key?("graphql") && info["graphql"].key?("user"))
				user_info = info["graphql"]["user"]

				@name = user_info["full_name"]
				@bio = user_info["biography"]
				@followers = user_info["edge_followed_by"]
				@following = user_info["edge_follow"]

				if (!File.exists?("cache/icons/#{username}.png"))
					pfp_url = user_info["profile_pic_url"]

					process_pfp(pfp_url, "cache/icons/#{username}.png")
				end
					
				@pfp = Gosu::Image.new("cache/icons/#{username}.png")
			end
		end

		def process_pfp(link, out)
			# Convert to PNG and resize to a temp file
			original = MiniMagick::Image.open(link)
			original.resize("150x150")
			original.format("png")
			original.write(out)

			# Apply the circle cutout and add a border
			MiniMagick::Tool::Convert.new do |icon|
				icon.size("150x150")
				icon << "xc:transparent"
				icon.fill("#9c9c9c")
				icon.draw("translate 75, 75 circle 0, 0, 75, 0")
				icon.fill(out)
				icon.draw("translate 75, 75 circle 0, 0, 73, 0")
				icon.trim()
				icon << out
			end
		end
	end

	class Conversation
		attr_reader :id, :participants, :users, :totals, :weekly_totals
		attr_accessor :title, :display_users, :graphs, :first_msg, :last_msg, :daily_messages

		def initialize(id, username, participants, messages)
			@id = id
			@username = username

			@participants = participants
			@users = Hash.new

			@totals = MessageTotals.new(@participants)
			@weekly_totals = Hash.new

			# Populated in viewer.rb
			@graphs = Hash.new

			@participants.each do |participant|
				if (!$user_cache.key?(participant))
					@users[participant] = $user_cache[participant] = User.new(participant)
				else
					@users[participant] = $user_cache[participant]
				end
			end

			if (messages)
				process_messages(messages)

				# Make the title *after* processing messages
				# to ensure that users who left group chats
				# are still included in the user count
				@title = make_title()

				@display_users = Array.new
				
				# Track the two users who sent the most messages
				first_place = 0
				first_place_user = nil

				second_place = 0
				second_place_user = nil

				@totals.sent.each do |user, score|
					if (score > first_place && (user != @username || @participants.length == 1))
						first_place = score
						first_place_user = user
					elsif (score > second_place && @participants.length > 2)
						second_place = score
						second_place_user = user
					end
				end

				if (first_place_user)
					@display_users[0] = first_place_user
					if (second_place_user)
						@display_users[1] = second_place_user
					end
				else
					@display_users[0] = @participants[0]
					if (@display_users[0] == username && participants.length > 1)
						@display_users[0] = @participants[1]
					end
				end
			end
		end

		def set_totals(totals, weekly_totals)
			@totals = totals
			@weekly_totals = weekly_totals
		end

		def +(other)
			totals = @totals + other.totals
			weekly_totals = Hash.new

			@weekly_totals.each do |week_key|
				weekly_totals[week_key] = @weekly_totals[week_key]
				if (other.weekly_totals.key?(week_key))
					weekly_totals[week_key] += other.weekly_totals[week_key]
				end
			end

			first_msg = @first_msg
			if (other.first_msg < first_msg)
				first_msg = other.first_msg
			end

			last_msg = @last_msg
			if (other.last_msg > last_msg)
				last_msg = other.last_msg
			end

			daily_messages = (@daily_messages + other.daily_messages) / 2

			convo = Conversation.new(@id, @username, @participants.clone, nil)
			convo.set_totals(totals, weekly_totals)
			
			convo.title = @title
			convo.display_users = @display_users

			convo.first_msg = first_msg
			convo.last_msg = last_msg
			convo.daily_messages = daily_messages

			return convo
		end

		# Users who leave a group chat aren't
		# included in the participant list
		def add_participant(username)
			if (!@participants.include?(username))
				@participants << username
				@totals.add_participant(username)

				# Retroactivly add the user to previous weekly totals
				@weekly_totals.each do |week_key, week_totals|
					week_totals.add_participant(username)
				end

				if (!$user_cache.key?(username))
					@users[username] = $user_cache[username] = User.new(username)
				else
					@users[username] = $user_cache[username]
				end
			end
		end

		def make_graphs
			self.weekly_totals_graph.write("cache/graphs/weekly-totals-#{@id}.png")
			self.likes_graph.write("cache/graphs/likes-#{@id}.png")
		end

		def likes_graph
			g = Gruff::StackedBar.new(1000)
			g.hide_title = true
			g.theme = {
				colors: %w["#e8de56" "#95e856" "#56e8b5" "#56e8d5" "#56b0e8" "#e89a56" "#9056e8" "#d756e8"],
	      marker_color: 'grey',
	      font_color: 'black',
	      background_colors: "transparent"
	    }

	    g.labels = @participants

	    labels = Hash.new
	    idx = 0

	    @participants.each do |participant|
	    	if (@totals.likes_given[participant] > 0)
		    	labels[idx] = participant
		    	idx += 1
		    end

		    if (@totals.likes_received[participant] > 0)
		    	detailed_likes = Array.new

		    	@participants.each do |other_participant|
		    		if (@totals.likes_given[other_participant] > 0)
		    			detailed_likes << @totals.detailed_likes[participant][other_participant]
		    		end
		    	end

		    	g.data(participant, detailed_likes)
		    end
	    end

	    g.labels = labels

			return g
		end

		def weekly_totals_graph
			g = Gruff::StackedBar.new(1000)
			g.hide_title = true
			g.theme = {
				colors: %w["#eb2a2a" "#4287f5"],
	      marker_color: 'grey',
	      font_color: 'black',
	      background_colors: "transparent"
	    }

			weekly_messages = Array.new
			weekly_likes = Array.new

			@weekly_totals.sort.each do |week_totals|
				week_likes = week_totals[1].total_likes

				weekly_messages << week_totals[1].total - week_likes
				weekly_likes << week_likes
			end

			g.data(:Likes, weekly_likes)
			g.data(:Messages, weekly_messages)

			return g
		end

		private

		def process_messages(messages)
			@first_msg = Date.today

			messages.length.times do |idx|
				message = messages[idx]
				sender = message["sender"]
				date = Date.parse(message["created_at"])

				if (date < @first_msg)
					@first_msg = date
				end

				# Always try to add the participant incase they are new
				add_participant(sender)

				# Track messages per-week (used for graphing)
				week_key = ((date.to_time - TWENTY_TEN) / 1.week).to_i
				week_totals = weekly_totals[week_key]

				if (!@weekly_totals.key?(week_key))
					week_totals = weekly_totals[week_key] = MessageTotals.new(@participants)
				end

				# Keep a total number of messages
				@totals.total += 1
				week_totals.total += 1

				# Keep track of messages sent vs received
				if (sender != @username)
					@totals.received += 1
					week_totals.received += 1
				end
					
				@totals.sent[sender] += 1
				week_totals.sent[sender] += 1

				# Process any likes that the message might have
				if (message.key?("likes"))
					message["likes"].each do |like|
						like_user = like["username"]
						add_participant(like_user)

						# Track the total number of likes
						@totals.total_likes += 1
						week_totals.total_likes += 1

						# Per-user likes given & received
						@totals.likes_given[like_user] += 1
						week_totals.likes_given[like_user] += 1

						@totals.likes_received[sender] += 1
						week_totals.likes_received[sender] += 1

						# Detailed likes hash connects sender & like user
						@totals.detailed_likes[sender][like_user] += 1
						week_totals.detailed_likes[sender][like_user] += 1
					end
				end
			end

			if (messages.length > 0)
				@last_msg = Date.parse(messages[0]["created_at"])

				first_week = ((@first_msg.to_time - TWENTY_TEN) / 1.week).to_i
				last_week = ((@last_msg.to_time - TWENTY_TEN) / 1.week).to_i
				
				(first_week..last_week).each do |week|
					if (!@weekly_totals.key?(week))
						@weekly_totals[week] = MessageTotals.new(@participants)
					end
				end

				@daily_messages = (@totals.total.to_f / (@last_msg - @first_msg)).round(2)
			else
				@last_msg = Date.today
				@daily_messages = 0
			end

		end

		def make_title
			if (@participants.length > 2)
				# Instagram doesn't provide group names
				return "Group (#{participants.length})"
			else
				title = @participants[0]

				# Make sure the title is not our username
				if (title == @username && @participants.length > 1)
					title = @participants[1]
				end

				# Remove long UUID from deleted users
				if (title.include?("__deleted__"))
					return "Deleted User"
				else
					return title
				end
			end
		end
	end

	def self.save_user_cache(user_cache)
		json_users = Array.new

		user_cache.each do |username, user|
			json_users << {
				"username" => user.username, 
				"name" => user.name,
				"bio" => user.bio,
				"pfp" => "icons/#{username}.png",
				"followers" => user.followers, 
				"following" => user.following
			}
		end

		File.open("cache/users.json", "w") do |file|
			file.write(json_users.to_json)
		end
	end

	def self.read_user_cache()
		json_users = JSON.parse(File.read("cache/users.json"))
		user_cache = Hash.new

		json_users.each do |u|
			pfp = nil
			pfp_file = "cache/#{u["pfp"]}"

			if (File.exists?(pfp_file))
				pfp = Gosu::Image.new(pfp_file)
			else
				pfp = Gosu::Image.new("assets/default.png")
			end
			user_cache[u["username"]] = User.new(u["username"], u["name"], u["bio"], pfp, u["followers"], u["following"])
		end

		return user_cache
	end

	def self.read_convos(filename, username)
		messages_hash = JSON.parse(File.read(filename))

		if (!File.exists?("cache"))
			Dir.mkdir("cache")
			Dir.mkdir("cache/icons")
		elsif (File.exists?("cache/users.json"))
			$user_cache = self.read_user_cache
		end

		convo_list = Array.new
		cur_id = 0

		messages_hash.each do |convo_hash|

			already_exists = false

			new_convo = Conversation.new(cur_id, username, convo_hash["participants"], convo_hash["conversation"])

			# Try to merge conversations with the same people
			convo_list.each do |convo|
				if (convo.participants.length == new_convo.participants.length)
					already_exists = true
					convo.participants.each do |participant|
						if (!new_convo.participants.include?(participant))
							already_exists = false
							break
						end
					end

					if (already_exists)
						# Combine the message totals
						convo += new_convo
						break
					end
				end
			end

			if (!already_exists)
				convo_list << new_convo
				cur_id += 1
			end
		end

		if (!File.exists?("cache/users.json"))
			self.save_user_cache($user_cache)
		end

		return convo_list
	end
end