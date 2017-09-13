require 'sinatra'
require "sinatra/reloader" if development?

$testDataFile = "/Users/petewood/Desktop/quiltin/testdata.txt"

def GetHeadersAndRows(rawData)
	rawRows = rawData.split("\n")

	rows = []

	rawRows.each { |rawRow|
		rawRow = rawRow.gsub /[\r\n]/, ''

		row = rawRow.split("\t")

		rows.push(row)
	}

	headers = rows.shift

	# Pad rows without the right number of elements to make life easier later
	rows.each { |row|
		if row.count != headers.count then
			row.fill('', row.count...headers.count)
		end
	}

	# Sort the rows by ballot number
	rows.sort! { |a, b| a[0].to_i <=> b[0].to_i }

	return { :headers => headers, :rows => rows }
end

def CheckBallots(data)
	$badBallots = []

	# { # => { :votes => [ [vote1, vote2], [vote1, vote2] ], $otherMetadata$ }
	ballots = {}

	data[:rows].each { |row|
		num = row.first

		if !ballots.has_key?(num) then
			ballots[num] = { :votes => [] }
		end

		ballots[num][:votes].push row
	}

	# Find ballot numbers where the contents don't match
	ballots.each { |num, ballot|
		mismatchCols = []

		for i in 1..ballot[:votes].count - 1 do
			for j in 0..ballot[:votes][0].count - 1 do
				if ballot[:votes][0][j] != ballot[:votes][i][j] then
					mismatchCols.push j
				end
			end
		end

		if !mismatchCols.empty? then
			ballot[:mismatchCols] = mismatchCols.dup
			$badBallots.push num
		end
	}

	# Find ballot numbers where there's only one ballot's worth of data
	$unverifiedBallots = ballots.select { |num, ballot| ballot[:votes].count < 2 }.keys

	$ballots = ballots
end

def TabulateResults(categories, ballots)
	# We have to remember that everything's 1-based for categories
	# since the first column header is the ballot number :)

	totals = []

	categories.each { |cat|
		if totals.empty? then
			totals.push({ :doNotUse => '' })
			next
		end

		totals.push({ :category => cat, :votes => [] })
	}

	ballots.each { |num, ballot|
		# Grab the results from the ballot
		results = ballot[:votes][0]

		for i in 1..results.count-1 do
			# Only count that ballot result if the result is valid
			next if ballot.has_key?(:mismatchCols) && ballot[:mismatchCols].include?(i)
			next if results[i] == ''

			totals[i][:votes].push results[i]
		end
	}

	$out << "<h2>Results</h2>"

	$out << <<-HTML
	<table>
		<tr>
			<th>Category</th>
			<th>Winner(s)</th>
			<th>Vote Distribution</th>
		</tr>
	HTML

	totals.each { |total|
		next if total.has_key?(:doNotUse)

		voteCounts = Hash[total[:votes].group_by {|x| x}.map {|k,v| [k,v.count]}]
		max_votes = voteCounts.values.max
		winners = voteCounts.select { |k, v| v == max_votes }.keys

		next if winners.empty?

		voteDistribution = voteCounts.sort_by {|k, votes| votes}.reverse.map { |k,v| "<strong>" + k + ":</strong> " + v.to_s }.join('; ')

		voteDistribution = "<strong>Category votes:</strong> " + total[:votes].count.to_s + "; " + voteDistribution

		$out << <<-HTML
		<tr>
			<td><strong>#{total[:category]}</strong></td>
			<td>#{winners.join(', ')}</td>
			<td class='allVotes'>#{voteDistribution}</td>
		</tr>
		HTML
	}

	$out << "</table>"

end

def ProcessData(rawData)
	$out = ""

	return if rawData.empty?

	data = GetHeadersAndRows(rawData)

	CheckBallots(data)

	TabulateResults(data[:headers], $ballots)

	$out << "<h2>Ballot Data</h2>"
	if !$badBallots.empty? then
		$out << "Ballots with unmatched data: " << $badBallots.join(', ') << "<br>"
	end
	if !$unverifiedBallots.empty? then
		$out << "Ballots with less than two entries: " << $unverifiedBallots.join(', ') << "<br>"
	end

	$out << "<br>" << TableizeBallots(data[:headers], $ballots)
end

def TableizeBallots(headers, ballots)
	str = '<table>'

	str << GenRow('th', headers)

	ballots.each { |num, ballot|
		str << GenBallotRow('td', ballot)
	}

	str << '</table>'
end

def Tableize(headers, rows)
	str = '<table>'

	str << GenRow('th', headers)

	rows.each { |row|
		str << GenRow('td', row)
	}

	str << '</table>'
end

def GenRow(element, row)
	str = '<tr'

	if $badBallots.include?(row[0]) then
		str << ' class="bad"'
	elsif $unverifiedBallots.include?(row[0]) then
		str << ' class="unverified"'
	end

	str << '>'

	row.each { |item| 
		str << '<' << element << '>' << item << '</' << element << '>'
	}

	str << '</tr>' << "\n"
end

def GenBallotRow(element, ballot)
	badCols = []

	if ballot.has_key?(:mismatchCols) then
		badCols = ballot[:mismatchCols]
	end

	str = ''

	ballot[:votes].each { |voteArray|
		str << '<tr'

		if ballot.has_key?(:mismatchCols) then
			str << ' class="bad"'
		elsif ballot[:votes].count < 2 then
			str << ' class="unverified"'
		end

		str << '>'

		for i in 0..voteArray.count - 1 do
			cl = ''
			
			if badCols.include?(i) then
				cl = ' class="mismatch"'
			end

			str << '<' << element << cl << '>' << voteArray[i] << '</' << element << '>'
		end

		str << '</tr>' << "\n"

		# No use printing multiple identical rows if the ballots match
		if !ballot.has_key?(:mismatchCols) then
			break
		end
	}

	return str
end

get '/' do
	$rawData = ''
	$out = ''

	if File.exist?($testDataFile)
		$rawData = File.read($testDataFile)
		ProcessData($rawData)
	end

	erb :page
end

post '/' do
	$out = ''
	$rawData = params[:data]

	ProcessData($rawData)

	erb :page
end
