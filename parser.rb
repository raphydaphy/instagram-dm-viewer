require "json"

messages_hash = JSON.parse(File.read("data/messages.json"))

total_messages = 0

messages_hash.each do |convo_hash|
	puts convo_hash["participants"].to_s()

	convo_hash["conversation"].each do
		total_messages += 1
	end
end

puts "Total Messages: #{total_messages.to_s()}"