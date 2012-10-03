class User extends Spine.Model
    @configure 'User', 'id', 'nick', 'current'

    validate: ->
        unless /^[\w\-]+$/.test(@nick)
            return "The nick should only contain alphanumeric characters, hyphens and underscores."

        if User.findByAttribute('nick', @nick)
            return 'This user already exists.'

class Message extends Spine.Model
    @configure 'Message', 'target', 'content'

class UserMessage extends Message
    @configure 'UserMessage', 'authorId', 'content'

    validate: ->
        unless User.exists(@authorId)
            "The user doesn't exist."

    constructor: ->
        super

        @target = User.find(@authorId).nick

class SystemMessage extends Message
    @configure 'SystemMessage'

##################################

class MessageView extends Spine.Controller
    constructor: ->
        super
        @el.addClass 'post'

        if @message.constructor.name == 'SystemMessage'
            @el.addClass 'system'

    data: ->
        author: @message.target
        content: @processMessage(@message.content)

    processMessage: (text) ->
        # rx = /((?:http|https):&#x2F;&#x2F;)?([a-z0-9-]+\.)?[a-z0-9-]+(\.[a-z]{2,6}){1,3}(&#x2F;(?:[a-z0-9.,_~#&=;%+?-]|&#x2F;)*)?/ig
        # Mustache.escape(text).replace rx, (match, protocol) ->
        rx = XRegExp('((?:http|https):&#x2F;&#x2F;)?([a-z0-9-\\p{L}]+\\.)?[a-z0-9-\\p{L}]+(\\.[a-z\\p{L}]{2,6}){1,3}(&#x2F;(?:[a-z0-9.,_~#&=;%+?-]|&#x2F;)*)?', 'ig')
        XRegExp.replace Mustache.escape(text), rx, (match, protocol) ->
            url = if protocol? then match else "//#{match}"
            "<a href=\"#{url}\" target=\"_blank\">#{match}</a>"

    render: =>
        @html Mustache.render($('#MessageTemplate').text(), @data())
        @

class UserList extends Spine.Controller
    constructor: ->
        super
        User.bind('refresh change', @render)

    data: ->
        count: User.count()
        users: User.all().map (user) =>
            current: user.current
            name: user.nick
            special: /majkel/i.test(user.nick)

    render: =>
        @html Mustache.render($('#UserListTemplate').text(), @data())
        @

class ChatApp extends Spine.Controller
    elements:
        '#ChatInput': 'input'
        '#ChatArea': 'posts'
        '.chatarea-wrapper': 'scrollArea'
        '#UserList': 'userlist'

    events:
        'submit #InputForm': 'submit'

    constructor: ->
        super

        # Automatically focus the input
        @input.focus()

        # Enable notifications on lost focus
        @unread = 0
        @focused = true
        @baseTitle = document.title
        @sound = new buzz.sound('/drip', formats: ['ogg', 'mp3'])
        $(document).on
            show: => 
                @focused = true
                @focusRestored()
            hide: => 
                @focused = false

        UserMessage.bind('create', @addMessage)
        SystemMessage.bind('create', @addMessage)

        @users = new UserList(el: @userlist)

        # Socket setup
        @socket = io.connect("#{location.protocol}//#{location.hostname}:8999")

        @socket.on 'connect', =>
            @socket.emit 'add user', {nick: @getNick()}, (data, users) =>
                @user = User.create(id: data.id, nick: data.nick, current: true)

                for uid, userdata of users
                    if uid != data.id
                        User.create(id: userdata.id, nick: userdata.nick, current: false)

        @socket.on 'log', (log) ->
            log.forEach (entry) ->
                SystemMessage.create(target: entry.nick, content: entry.content)

        @socket.on 'user connected', (data) =>
            data.current = false
            User.create data unless User.exists(data.id)

            SystemMessage.create(target: data.nick, content: 'has just connected')
        @socket.on 'user disconnected', (data) ->
            User.destroy data.id

            SystemMessage.create(target: data.nick, content: 'has disconnected')
        @socket.on 'nick changed', (data) ->
            User.update data.id, nick: data.nick

            SystemMessage.create(target: data.oldNick, content: 'is now called ' + data.nick)

        @socket.on 'chat', (msg) =>
            UserMessage.create msg
            @notify() unless @focused

    submit: (e) ->
        e.preventDefault()
        value = @input.val()

        return if value == ''

        # Check if posted a command
        match = value.match(/^\/(\w+)(?:\s+(.+))?$/)
        if match
            @handleCommand(command: match[1], argument: match[2])
        else
            UserMessage.create(authorId: @user.id, content: value)
            @socket.emit 'chat', {content: value}

        @input.val('')

    handleCommand: (cmd) ->
        switch cmd.command
            when 'nick'
                oldNick = @user.nick
                @user.nick = cmd.argument.replace(/\s+$/, '')

                if @user.save()
                    @socket.emit 'change nick', {id: @user.id, nick: @user.nick}
                    if localStorage
                        localStorage.setItem('nick', @user.nick)

                    SystemMessage.create(target: oldNick, content: 'is now called ' + @user.nick)
                else
                    @user.nick = oldNick
                    SystemMessage.create(target: oldNick, content: 'could not change his nick. ' + @user.validate())
            else
                SystemMessage.create(target: @user.nick, content: 'tried to use an unknown command')

    addMessage: (msg) =>
        view = new MessageView(message: msg)
        @posts.append(view.render().el)
        @scrollArea.scrollTop(@posts.height())

    focusRestored: ->
        document.title = @baseTitle
        @unread = 0

    notify: ->
        document.title = "(#{++@unread}) #{@baseTitle}"
        @sound.play()

    getNick: ->
        if localStorage && localStorage.getItem('nick')
            nick = localStorage.getItem('nick')
            if User.findByAttribute('nick', nick)
                @randomizeNick()
            else
                nick
        else
            @randomizeNick()

    randomizeNick: ->
        index = Math.floor(Math.random() * 100000);
        "guest#{index}"

#########################################

$ -> new ChatApp(el: $('#Viewport'))