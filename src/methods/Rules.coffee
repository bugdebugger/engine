# CSS rules and conditions
Parser = require '../concepts/Parser'


class Rules
  
  # Comma combines results of multiple selectors without duplicates
  ',':
    # If all sub-selectors are native, make a single comma separated selector
    group: '$query'

    # Separate arguments with commas during serialization
    separator: ','

    serialized: true

    # Dont let undefined arguments stop execution
    eager: true

    before: 'onBeforeQuery'
    after: 'onQuery'
    init: 'onSelector'

    # Return deduplicated collection of all found elements
    command: (operation, continuation, scope, meta) ->
      debugger 
      contd = @getScopePath(continuation) + operation.path

      if @queries.ascending
        index = @engine.indexOfTriplet(@queries.ascending, operation, contd, scope) == -1
        if index > -1
          @queries.ascending.splice(index, 3)

      return @queries[contd]

    # Recieve a single element found by one of sub-selectors
    # Duplicates are stored separately, they dont trigger callbacks
    capture: (result, operation, continuation, scope, meta, ascender) ->
      debugger 
      contd = @getScopePath(continuation) + operation.parent.path
      @queries.add(result, contd, operation.parent, scope, operation.index)
      console.info('add', operation.index, operation)
      @queries.ascending ||= []
      if @engine.indexOfTriplet(@queries.ascending, operation.parent, contd, scope) == -1
        @queries.ascending.push(operation.parent, contd, scope)
      return true

    # Remove a single element that was found by sub-selector
    # Doesnt trigger callbacks if it was also found by other selector
    release: (result, operation, continuation, scope) ->
      contd = @getScopePath(continuation) + operation.parent.path
      console.error('remove', operation.index, operation, )
      debugger
      @queries.remove(result, contd, operation.parent, scope, operation.index)
      return true

  # CSS rule
  
  "rule":
    bound: 1

    # Set rule body scope to a found element
    solve: (operation, continuation, scope, meta, ascender, ascending) ->
      if operation.index == 2 && !ascender && ascending?
        @expressions.solve operation, continuation, ascending, operation
        return false

    # Capture commands generated by css rule conditional branch
    capture: (result, parent, continuation, scope) ->
      if !result.nodeType && !@isCollection(result) && typeof result != 'string'
        @engine.provide result
        return true

    onAnalyze: (operation) ->
      parent = operation.parent || operation
      while parent?.parent      
        parent = parent.parent
      operation.sourceIndex = parent.rules = (parent.rules || 0) + 1

  "scoped":
    # Set rule body scope to a found element
    solve: (operation, continuation, scope, meta, ascender, ascending) ->
      if operation.index == 2 && !ascender && ascending?
        @expressions.solve operation, continuation, ascending, operation
        return false
    

  ### Conditional structure 

  Evaluates one of two branches
  chosen by truthiness of condition.

  Structurally invisible to solver, 
  it leaves trail in continuation path
  ###

  'if':
    # Resolve all values in first argument
    primitive: 1

    cleaning: true

    solve: (operation, continuation, scope, meta, ascender, ascending) ->
      return if @ == @solved
      
      for arg in operation.parent
        if arg[0] == true
          arg.shift()

      if operation.index == 1 && !ascender
        unless condition = operation.condition 
          operation.condition = condition = @clone operation
          condition.parent = operation.parent
          condition.index = operation.index
          condition.domain = operation.domain
        @solved.solve condition, continuation, scope
        return false

    update: (operation, continuation, scope, meta, ascender, ascending) ->
      operation.parent.uid ||= '@' + (@engine.methods.uid = (@engine.methods.uid ||= 0) + 1)
      path = continuation + operation.parent.uid
      id = scope._gss_id
      watchers = @queries.watchers[id] ||= []
      if !watchers.length || @indexOfTriplet(watchers, operation.parent, continuation, scope) == -1
        watchers.push operation.parent, continuation, scope

      condition = ascending && (typeof ascending != 'object' || ascending.length != 0)
      index = condition && 2 || 3
      
      old = @queries[path]
      if !!old != !!condition || (old == undefined && old != condition)
        d = @pairs.dirty
        unless old == undefined
          @queries.clean(@getContinuation(path) , continuation, operation.parent, scope)
        @queries[path] = condition
        if !d && (d = @pairs.dirty)
          @pairs.onBeforeSolve()
          @updating.paired = undefined
          @updating.queries = undefined


    

        @engine.console.group '%s \t\t\t\t%o\t\t\t%c%s', (condition && 'if' || 'else') + @engine.DESCEND, operation.parent[index], 'font-weight: normal; color: #999', continuation
        
        if branch = operation.parent[index]
          result = @document.solve(branch, @getContinuation(path, null,  @DESCEND), scope, meta)
          @updating.paired = undefined
          @pairs?.onBeforeSolve()
          @queries?.onBeforeSolve()
        @console.groupEnd(path)

    # Capture commands generated by evaluation of arguments
    capture: (result, operation, continuation, scope, meta) ->
      # Condition result bubbled up, pick a branch
      if operation.index == 1
        if continuation?
          @document.methods.if.update.call(@document, operation.parent[1], @getContinuation(continuation, null, @DESCEND), scope, meta, undefined, result)
        return true
      else
      # Capture commands bubbled up from branches
        if typeof result == 'object' && !result.nodeType && !@isCollection(result)
          @provide result
          return true
        

  "text/gss-ast": (source) ->
    return JSON.parse(source)

  "text/gss": (source) ->
    return Parser.parse(source)?.commands

  "text/gss-value": -> (source)
    # Parse value
    parse: (value) ->
      unless (old = (@parsed ||= {})[value])?
        if typeof value == 'string'
          if match = value.match(StaticUnitRegExp)
            return @parsed[value] = @[match[2]](parseFloat(match[1]))
          else
            value = 'a: == ' + value + ';'
            return @parsed[value] = Parser.parse(value).commands[0][2]
        else return value
      return old

  StaticUnitRegExp: /^(-?\d+)(px|pt|cm|mm|in)$/i


  # Evaluate stylesheet
  "eval": 
    command: (operation, continuation, scope, meta, 
              node, type = 'text/gss', source, label = type) ->
      if node.nodeType
        if nodeType = node.getAttribute('type')
          type = nodeType
        source ||= node.textContent || node 
        if (nodeContinuation = node._continuation)?
          @queries.clean(nodeContinuation)
          continuation = nodeContinuation
        else if !operation
          continuation = @getContinuation(node.tagName.toLowerCase(), node)
        else
          continuation = node._continuation = @getContinuation(continuation || '', null,  @engine.DESCEND)
        if node.getAttribute('scoped')?
          scope = node.parentNode

      rules = @clone @['_' + type](source)
      console.log(1, rules)
      @engine.engine.solve(rules, continuation, scope)

      return

  # Load & evaluate stylesheet
  "load": 
    command: (operation, continuation, scope, meta, 
              node, type, method = 'GET') ->
      src = node.href || node.src || node
      type ||= node.type || 'text/gss'
      xhr = new XMLHttpRequest()
      xhr.onreadystatechange = =>
        if xhr.readyState == 4 && xhr.status == 200
          @eval.command.call(@, operation, continuation, scope, meta,
                                node, type, xhr.responseText, src)
      xhr.open(method.toUpperCase(), src)
      xhr.send()

for property, fn of Rules::
  fn.rule = true



module.exports = Rules