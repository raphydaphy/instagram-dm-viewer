require "rubygems"
require "gosu"
require "./parser.rb"
require "./gui.rb"

TOTAL_PAGES = 2

class Window < Gosu::Window
	def initialize(convo_list, username)
		super(840, 520, {:resizable => true})

		self.caption = "Instagram DM Stats"

		@background_color = Gosu::Color::WHITE

		@font = Gosu::Font.new(15)
		@heading_font = Gosu::Font.new(20, {:bold => true})

		@sidebar_hover_color = Gosu::Color.argb(0xff_e6e6e6)
		@text_color = Gosu::Color::BLACK

		@username = username

		@convo_list = convo_list
		@selected_convo = -1

		@sidebar_scroll = 0
		@max_scroll = @convo_list.length * 30

		arrow_font = Gosu::Font.new(20)
		sidebar_width = self.calc_sidebar_width

		@left_arrow = Gui::Button.new(sidebar_width + 30, 7.5, 50, 25, arrow_font, "<")
		@right_arrow = Gui::Button.new(self.width - 80, 7.5, 50, 25, arrow_font, ">")

		@info_page = 0
	end

	def calc_sidebar_width
		return [self.width * 0.2, 150].max
	end

	def draw_sidebar(sidebar_width)
		sidebar_y = 55 - @sidebar_scroll

		Gosu.draw_rect(sidebar_width, 0, 1, self.height, Gosu::Color::BLACK, Gui::ZOrder::MIDDLE)
		Gosu.draw_rect(0, 40, sidebar_width, 1, Gosu::Color::BLACK, Gui::ZOrder::MIDDLE)

		@convo_list.each do |convo|
			hovered = (mouse_x >= 0 && mouse_x < sidebar_width && mouse_y >= sidebar_y - 7.5 && mouse_y < sidebar_y + 22.5)

			if (convo.id == @selected_convo || hovered)
				Gosu.draw_rect(0, sidebar_y - 7.5, sidebar_width, 30, @sidebar_hover_color, Gui::ZOrder::MIDDLE)
			end

			@font.draw_markup(convo.title, 10, sidebar_y, Gui::ZOrder::TOP, 1, 1, @text_color)
			sidebar_y += 30
		end

		Gosu.draw_rect(0, 0, sidebar_width, 40, Gosu::Color::WHITE, Gui::ZOrder::TOP)
		@heading_font.draw_markup("Conversations", 10, 10, Gui::ZOrder::TOP, 1, 1, @text_color)
	end

	def draw_graph(convo, graph, sidebar_width)
		graph_scale = (self.width - sidebar_width - 30) / 1000.0
		convo.graphs[graph].draw(sidebar_width + 15, 40, Gui::ZOrder::TOP, graph_scale, graph_scale)
	end

	def draw_convo(sidebar_width)
		if (@selected_convo != -1)
			convo = @convo_list[@selected_convo]
			is_group = convo.participants.length > 2

			page_title = "Conversation with #{convo.title}"

			if (is_group)
				page_title = "Unnamed group with #{convo.participants.length} members"
			end

			case @info_page
			when 0
				convo_info = "<b>Conversation Stats</b>"
				convo_info += "\n\nTotal Messages: #{convo.totals.total}"
				convo_info += "\nSent: #{convo.totals.sent}"
				convo_info += "\nReceived: #{convo.totals.received}"

				convo_info += "\n\nTotal Likes: #{convo.totals.total_likes}"

				if (is_group)
					convo_info += "\n\nParticipants:"
					convo.participants.each do |participant|
						convo_info += "\n - #{participant} (#{convo.totals.likes_received[participant]}/#{convo.totals.likes_given[participant]} likes)"
					end
				else
					convo_info += "\nLikes Given: #{convo.totals.likes_given[@username]}"
					convo_info += "\nLikes Received: #{convo.totals.likes_received[@username]}"
				end

				convo_info += convo.first_msg.strftime("\n\nFirst Message: %d/%m/%Y")
				convo_info += convo.last_msg.strftime("\nLast Message: %d/%m/%Y")
				convo_info += "\nDaily Messages: #{convo.daily_messages}"

				@font.draw_markup(convo_info, sidebar_width + 15, 40, Gui::ZOrder::TOP, 1, 1, @text_color)
			when 1
				page_title = "Weekly Stats"
				draw_graph(convo, "weekly_totals", sidebar_width)
			when 2
				page_title = "Likes Breakdown"
				draw_graph(convo, "likes", sidebar_width)
			end

			if (@info_page > 0)
				@left_arrow.draw()
			end

			if (@info_page < TOTAL_PAGES)
				@right_arrow.draw()
			end

			Gui::draw_centered_string(@heading_font, page_title, sidebar_width / 2 + self.width / 2, 10, @text_color)
		end
	end

	def draw
		Gosu.draw_rect(0, 0, self.width, self.height, @background_color, Gui::ZOrder::BG)

		sidebar_width = self.calc_sidebar_width

		draw_sidebar(sidebar_width)
		draw_convo(sidebar_width)
	end

	def update
		@left_arrow.x = self.calc_sidebar_width + 30
		@right_arrow.x = self.width - 80

		@left_arrow.update(mouse_x, mouse_y)
		@right_arrow.update(mouse_x, mouse_y)
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
		elsif (id == Gosu::MS_LEFT)
			if (@left_arrow.mouse_over?(mouse_x, mouse_y))
				if (@info_page > 0)
					@info_page -= 1
				end
			elsif (@right_arrow.mouse_over?(mouse_x, mouse_y))
				if (@info_page < TOTAL_PAGES)
					@info_page += 1
				end
			end
		end
	end
end

print("Enter your Instagram username: ")
username = gets.chomp()

convo_list = IGParser::read_convos("data/messages.json", username)

if (!File.exists?("cache/graphs"))
	Dir.mkdir("cache/graphs")
	convo_list.each do |convo|
		convo.make_graphs()
	end
end

convo_list.each do |convo|
	convo.graphs["weekly_totals"] = Gosu::Image.new("cache/graphs/weekly-totals-" + convo.id.to_s() + ".png")
	convo.graphs["likes"] = Gosu::Image.new("cache/graphs/likes-" + convo.id.to_s() + ".png")
end

Window.new(convo_list, username).show()