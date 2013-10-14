$A = (list) -> Array.prototype.slice.call(list)
$F = (n, digits=4) ->
  scale = Math.pow(10, digits)
  '' + Math.round(n * scale) / scale
$Z = (n, width=2) ->
  s = '' + n
  if s.length >= width
    s
  else
    s = '0000000' + s
    return s.substr(s.length - width)



class Prediction
  constructor: (@depth, @choiceWeights, @children=[]) ->
    sum = @choiceWeights.reduce((a, b) -> a + b)
    if sum > 0
      @choiceWeights = (w / sum for w in @choiceWeights)

    @bestChoiceIndex = 0
    for choiceIndex in [1 ... @choiceWeights.length]
      if @choiceWeights[choiceIndex] > @choiceWeights[@bestChoiceIndex]
        @bestChoiceIndex = choiceIndex

  describe: (choices) ->
    description = "D=#{$Z @depth}  { " + (@_describeChoice(choices, i) for i in [0 ... @choiceWeights.length]).join(",  ") + " }"

    if @children.length == 0
      return description
    else
      return [description].concat(c.describe(choices) for c in @children).join("\n")

  _describeChoice: (choices, i) ->
    choice = choices[i]
    if i == @bestChoiceIndex
      choice = choice.toUpperCase()
    else
      choice = choice.toLowerCase()
    return "#{choice}: #{$F @choiceWeights[i]}"

  @merge = (predictions) ->
    choiceCount = predictions[0].choiceWeights.length

    weigths =
      for i in [0 ... choiceCount]
        weigthsOfThisChoice = (p.choiceWeights[i] for p in predictions)
        Math.max.apply(Math, weigthsOfThisChoice)

    return new Prediction('--', weigths, predictions)



class Predictor
  constructor: (@depth, @choiceCount) ->
    @stateCount = Math.pow(@choiceCount, depth)
    @statistics = new Int32Array(@stateCount)
    @curState = 0
    @shiftedState = 0

  record: (choiceIndex) ->
    @curState = @shiftedState + choiceIndex
    @shiftedState = @_shiftState(@curState)

    @statistics[@curState] += 1

  predict: ->
    weights = (@statistics[@shiftedState + i] for i in [0 ... @choiceCount])
    return new Prediction(@depth, weights)

  describe: (choices) ->
    list = []
    path = []
    @_describeHelper(choices, list, @depth, path, 0)
    return list.join("\n")

  _describeHelper: (choices, list, depth, path, state) ->
    if depth == 0
      list.push path.join(' ') + ' -> ' + @statistics[state]
    else
      for i in [0 ... @choiceCount]
        path.push(choices[i])
        @_describeHelper choices, list, depth-1, path, @_shiftState(state) + i
        path.pop()

  _shiftState: (state) ->
    return state * @choiceCount % @stateCount



class MultiDepthPredictor
  constructor: (@maxDepth, @choiceCount) ->
    @layers = (new Predictor(depth, @choiceCount) for depth in [1 .. @maxDepth])

  record: (choiceIndex) ->
    for layer in @layers
      layer.record(choiceIndex)

  predict: ->
    predictions = (layer.predict() for layer in @layers)
    return Prediction.merge(predictions)

  describe: (choices) ->
    (layer.describe(choices) for layer in @layers).join("\n\n")


class GameUI
  constructor: (rootEl, @options) ->
    @choiceButtons = $A(rootEl.querySelectorAll('.choice'))
    @stateEl = rootEl.querySelector('#state')
    @logEl = rootEl.querySelector('#log')
    @messageEl = rootEl.querySelector('#message')
    @bulkInputEl = rootEl.querySelector('#bulk-input')
    @bulkOutputEl = rootEl.querySelector('#bulk-output')

    @options.choices = @choiceButtons.map((button) -> button.textContent)

    @choiceButtons.forEach (choiceButton, choiceIndex) =>
      choiceButton.addEventListener 'click', @makeMove.bind(@, choiceIndex), no

    document.addEventListener 'keypress', (e) =>
      if e.ctrlKey or e.altKey or e.shiftKey or e.metaKey
        return

      ch = String.fromCharCode(e.keyCode).toUpperCase()
      if ch >= '0' && ch <= '9'
        index = parseInt(ch, 10) - 1
        if index >= @game.choices.length
          return
      else
        index = @game.choices.indexOf(ch)
        if index < 0
          return

      @makeMove(index)

    document.querySelector('#bulk-run').addEventListener 'click', @runBulk, no
    document.querySelector('#bulk-random').addEventListener 'click', @runRandomBulkInput, no

    @reset()
    @generateRandomBulkInput()

  generateRandomBulkInput: ->
    bulkLength = 100
    choices = @game.choices
    @bulkInputEl.value = @game.indexesToMoves(Math.floor(Math.random() * choices.length) for i in [1 ... bulkLength]).join('')

  runRandomBulkInput: =>
    @generateRandomBulkInput()
    @runBulk()

  reset: ->
    @game = new Game(this, @options)

  start: ->
    @_update()

  makeMove: (choiceIndex) ->
    @game.makeMove(choiceIndex)
    @_update()

  runBulk: =>
    bulkMoves = @game.movesToIndexes(@bulkInputEl.value.split(''))
    @reset()
    for move in bulkMoves
      @game.makeMove(move)
    @_update()

    @bulkInputEl.value = @game.indexesToMoves(@game.moves).join('')
    @bulkOutputEl.textContent = @game.indexesToMoves(@game.predictions).join('')

  _update: ->
    if @game.lastPrediction
      lastPredictedMove = @game.choices[@game.lastPrediction.bestChoiceIndex]
      lastActualMove = @game.choices[@game.lastMoveIndex]
      if lastPredictedMove == lastActualMove
        message = "I've picked #{lastPredictedMove} — correctly!"
      else
        message = "I've picked #{lastPredictedMove}, but you picked #{lastActualMove} — my bad :-("
    else
      message = "Please make your first move!"

    @messageEl.textContent = message

    winningPercentage = (if @game.rounds == 0 then 0 else @game.wins / @game.rounds * 100)
    rollingWinsPercentage = (if @game.rollingRounds == 0 then 0 else @game.rollingWins / @game.rollingRounds * 100)
    @stateEl.textContent =
      "Recent wins  #{@game.rollingWins} of #{@game.rollingRounds}, #{$F(rollingWinsPercentage, 1)}%\n" +
      "Overall wins #{@game.wins} of #{@game.rounds}, #{$F(winningPercentage, 1)}%\n\n" +
      @game.nextPrediction.describe(@game.choices) + "\n\n" + @game.describe()



class Game
  constructor: (@ui, @options) ->
    @choices = @options.choices

    @predictor = new MultiDepthPredictor(@options.maxDepth, @choices.length)
    # @predictor = new Predictor(2, @choices.length)
    @ui = null

    @moves = []
    @predictions = []

    @wins = 0
    @rounds = 0
    @rollingWinLimit = 10
    @rollingWinStats = []

    @lastPrediction = null
    @nextPrediction = null
    @lastMoveIndex = null

    @_updatePrediction()


  makeMove: (choiceIndex) ->
    @lastPrediction = @nextPrediction

    @lastMoveIndex = choiceIndex
    @moves.push(choiceIndex)
    @predictions.push(@lastPrediction.bestChoiceIndex)

    @predictor.record(choiceIndex)

    isWinning = (choiceIndex == @lastPrediction.bestChoiceIndex)
    @_recordResult(isWinning)

    @_updatePrediction()


  _recordResult: (isWinning) ->
    @rounds += 1
    if isWinning
      @wins += 1

    @rollingWinStats.push(isWinning)
    if @rollingWinStats.length > @rollingWinLimit
      @rollingWinStats.splice(0, @rollingWinStats.length - @rollingWinLimit)

    @rollingRounds = @rollingWinStats.length
    @rollingWins = ~~@rollingWinStats.reduce((a,b) -> a + b)

  _updatePrediction: ->
    @nextPrediction = @predictor.predict()

  indexesToMoves: (indexes) ->
    (@choices[i] for i in indexes)

  movesToIndexes: (moves) ->
    (@choices.indexOf(move) for move in moves)

  describe: ->
    if @options.maxDepth < 5
      @predictor.describe(@choices)
    else
      ''

new GameUI(document, { maxDepth: 20 }).start()

