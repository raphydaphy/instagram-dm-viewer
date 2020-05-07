require "rubygems"
require "gosu"
require "json"

print("Enter your instagram username: ")
$username = gets.chomp()

class Conversation
	attr_reader :participants, :id, :messages
	attr_accessor :title

	def initialize(id, participants, messages)
		@id = id
		@participants = participants
		@messages = messages

		if (participants.length > 2)
			@title = "Group (#{participants.length})"
		else
			@title = @participants[0]
			if (@title == $username && @participants.length > 1)
				@title = @participants[1]
			end

			if (@title.include?("__deleted__"))
				@title = "Deleted User"
			end
		end
	end
end

def read_convos(filename)
	messages_hash = JSON.parse(File.read(filename))

	convo_list = Array.new
	cur_id = 0

	messages_hash.each do |convo_hash|
		convo_participants = convo_hash["participants"]
		convo_messages = convo_hash["conversation"]

		already_exists = false

		# Try to merge conversations with the same people
		convo_list.each do |convo|
			if (convo.participants.length == convo_participants.length)
				already_exists = true
				convo.participants.each do |participant|
					if (!convo_participants.include?(participant))
						already_exists = false
						break
					end
				end

				if (already_exists)
					convo.messages << convo_messages
					break
				end
			end
		end

		if (!already_exists)
			convo_list << Conversation.new(cur_id, convo_participants, convo_messages)
			cur_id += 1
		end
	end

	return convo_list
end

module ZOrder
  BG, MIDDLE, TOP = *0..2
end

class Window < Gosu::Window
	def initialize
		super(720, 480, {:resizable => true})

		self.caption = "Instagram DM Viewer"

		@background_color = Gosu::Color::WHITE

		@font = Gosu::Font.new(15)
		@heading_font = Gosu::Font.new(20, {:bold => true})

		@sidebar_hover_color = Gosu::Color.argb(0xff_e6e6e6)
		@text_color = Gosu::Color::BLACK

		@convo_list = read_convos("data/messages.json")
		@selected_convo = -1

		@sidebar_scroll = 0
		@max_scroll = @convo_list.length * 30
	end

	def calc_sidebar_width
		return [self.width * 0.2, 150].max
	end

	def draw_sidebar

		sidebar_width = self.calc_sidebar_width
		sidebar_y = 55 - @sidebar_scroll

		Gosu.draw_rect(sidebar_width, 0, 1, self.height, Gosu::Color::BLACK, ZOrder::MIDDLE)
		Gosu.draw_rect(0, 40, sidebar_width, 1, Gosu::Color::BLACK, ZOrder::MIDDLE)

		@convo_list.each do |convo|
			hovered = (mouse_x >= 0 && mouse_x < sidebar_width && mouse_y >= sidebar_y - 7.5 && mouse_y < sidebar_y + 22.5)

			if (convo.id == @selected_convo || hovered)
				Gosu.draw_rect(0, sidebar_y - 7.5, sidebar_width, 30, @sidebar_hover_color, ZOrder::MIDDLE)
			end

			@font.draw_markup(convo.title, 10, sidebar_y, ZOrder::TOP, 1, 1, @text_color)
			sidebar_y += 30
		end

		Gosu.draw_rect(0, 0, sidebar_width, 40, Gosu::Color::WHITE, ZOrder::TOP)
		@heading_font.draw_markup("Conversations", 10, 10, ZOrder::TOP, 1, 1, @text_color)

		if (@selected_convo != -1)
			convo = @convo_list[@selected_convo]
			is_group = convo.participants.length > 2

			long_title = "Conversation with #{convo.title}"

			if (is_group)
				long_title = "Unnamed group with #{convo.participants.length} members"
			end

			@heading_font.draw_markup(long_title, sidebar_width + 15, 10, ZOrder::TOP, 1, 1, @text_color)

			convo_info = "Total Messages: #{convo.messages.length}"

			if (is_group)
				convo_info += "\n\nParticipants:"
				convo.participants.each do |participant|
					convo_info += "\n - #{participant}"
				end
			end
			
			@font.draw_markup(convo_info, sidebar_width + 15, 40, ZOrder::TOP, 1, 1, @text_color)
		end
	end

	def draw
		Gosu.draw_rect(0, 0, self.width, self.height, @background_color, ZOrder::BG)
		draw_sidebar()
	end

	def update
	end

	def needs_cursor?
		return true
	end

	def button_down(id)
		# If the mouse is over the sidebar
		if (mouse_y > 40 && mouse_x < self.calc_sidebar_width)
			# Handle sidebar scrolling
			if (id == Gosu::MS_WHEEL_DOWN || id == Gosu::MS_WHEEL_UP)
				if (id == Gosu::MS_WHEEL_DOWN)
					@sidebar_scroll += 15
				else
					@sidebar_scroll -= 15
				end

				# Prevent scrolling out of bounds
				if (@sidebar_scroll < 0)
					@sidebar_scroll = 0
				elsif (@sidebar_scroll > @max_scroll - self.height + 55)
					@sidebar_scroll = @max_scroll - self.height + 55
				end
			elsif (id == Gosu::MS_LEFT)
				hovered_index = ((mouse_y + @sidebar_scroll - 47.5) / 30).floor
				if (hovered_index < @convo_list.length)
					@selected_convo = hovered_index
				end
	  	end
		end
	end
end

Window.new.show()