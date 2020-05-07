require "rubygems"
require "gruff"
require "json"
require "date"
require 'active_support/core_ext/numeric/time'

module IGParser
	# Instagram was released in 2010
	TWENTY_TEN = Date.new(2010, 1, 1).to_time

	class MessageTotals
		attr_accessor :total, :sent, :received, :total_likes, :likes_given, :likes_received

		def initialize(participants)
			@total = @sent = @received = @total_likes = 0
			@likes_given = Hash.new
			@likes_received = Hash.new

			participants.each do |participant|
				@likes_given[participant] = 0
				@likes_received[participant] = 0
			end
		end

		# Combine two seperate like totals from the same conversation
		def +(other)
			totals = MessageTotals.new(Array.new)

			totals.total = @total + other.total
			totals.sent = @sent + other.sent
			totals.received = @received + other.received
			totals.total_likes = @total_likes + other.total_likes
			totals.likes_given = Hash.new
			totals.likes_received = Hash.new

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

			return totals
		end
	end

	class Conversation
		attr_reader :participants, :id, :totals, :weekly_totals
		attr_accessor :title, :graphs

		def initialize(id, username, participants, messages)
			@id = id
			@username = username
			@participants = participants

			@totals = MessageTotals.new(@participants)
			@weekly_totals = Hash.new

			# Populated in viewer.rb
			@graphs = Hash.new

			if (messages)
				process_messages(messages)

				# Make the title *after* processing messages
				# to ensure that users who left group chats
				# are still included in the user count
				@title = make_title()
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

			convo = Conversation.new(@id, @username, @participants.clone, nil)
			convo.set_totals(totals, weekly_totals)
			convo.title = @title

			return convo
		end

		# Users who leave a group chat aren't
		# included in the participant list
		def add_participant(username)
			if (!@participants.include?(username))
				@participants << username
				@totals.likes_given[username] = 0
				@totals.likes_received[username] = 0

				# Retroactivly add the user to previous weekly totals
				@weekly_totals.each do |week_key, week_totals|
					week_totals.likes_given[username] = 0
					week_totals.likes_received[username] = 0
				end
			end
		end

		def make_graph
			g = Gruff::StackedBar.new(1000)
			g.title = "Weekly Stats"
			g.theme = {
				colors: %w[red aqua],
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

			g.write("graphs/#{@id}.png")
		end

		def process_messages(messages)
			messages.length.times do |idx|
				message = messages[idx]
				sender = message["sender"]
				date = Date.parse(message["created_at"]).to_time

				# Always try to add the participant incase they are new
				add_participant(sender)

				# Track messages per-week (used for graphing)
				week_key = (date - TWENTY_TEN) / 1.week
				week_totals = weekly_totals[week_key]

				if (!@weekly_totals.key?(week_key))
					week_totals = weekly_totals[week_key] = MessageTotals.new(@participants)
				end

				# Keep a total number of messages
				@totals.total += 1
				week_totals.total += 1

				# Keep track of messages sent vs received
				if (sender == @username)
					@totals.sent += 1
					week_totals.sent += 1
				else
					@totals.received += 1
					week_totals.sent += 1
				end

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
					end
				end
			end
		end

		private

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

	def self.read_convos(filename, username)
		messages_hash = JSON.parse(File.read(filename))

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

		return convo_list
	end
end