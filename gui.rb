module Gui
  module ZOrder
    BG, MIDDLE, TOP = *0..2
  end

  class Button
    attr_accessor :x, :y, :width, :height
    attr_reader :text, :hovered

    @text_width = 0
    @hovered = false

    @@color = Gosu::Color.argb(0xff_e6e6e6)
    @@border_color = Gosu::Color::BLACK
    @@text_color = Gosu::Color::BLACK

    def initialize(x, y, width, height, font, text)
      @x = x
      @y = y
      @width = width
      @height = height
      @font = font

      self.text = text
    end

    def draw()
      if (@hovered)
        # Draw a thin outline when the mouse overlaps the button
        Gosu.draw_rect(@x - 1, @y - 1, @width + 2, @height + 2, @@border_color, ZOrder::MIDDLE)
      end

      # Draw the button
      Gosu.draw_rect(@x, @y, @width, @height, @@color, ZOrder::MIDDLE)

      # Position the text in the center
      text_x = @x + @width / 2 - @text_width / 2
      text_y = @y + @height / 2 - @font.height / 2

      # Draw the button text
      @font.draw_text(@text, text_x, text_y, ZOrder::TOP, 1.0, 1.0, @@text_color)
    end

    def update(mouse_x, mouse_y)
      @hovered = mouse_over?(mouse_x, mouse_y)
    end

    def mouse_over?(mouse_x, mouse_y)
      return mouse_x >= @x && mouse_x < @x + @width && mouse_y >= @y && mouse_y < @y + @height
    end

    # Automatically recalculate text width when the text is changed
    def text=(text)
      @text = text

      if (@font)
        @text_width = @font.text_width(@text)
      end
    end
  end

  def self.draw_centered_string(font, text, x, y, color=Gosu::Color::BLACK)
    width = font.text_width(text)
    font.draw_markup(text, x - width / 2, y, ZOrder::TOP, 1, 1, color)
  end
end