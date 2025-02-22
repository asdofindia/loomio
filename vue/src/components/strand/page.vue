<script lang="coffee">
import Records           from '@/shared/services/records'
import Session           from '@/shared/services/session'
import EventBus          from '@/shared/services/event_bus'
import AbilityService    from '@/shared/services/ability_service'
import ThreadLoader      from '@/shared/loaders/thread_loader'

export default
  data: ->
    discussion: null
    loader: null
    position: 0
    group: null
    discussionFetchError: null
    lastFocus: null

  mounted: -> @init()

  watch:
    '$route.params.key': 'init'
    '$route.params.comment_id': 'init'
    '$route.params.sequence_id': 'respondToRoute'
    '$route.params.comment_id': 'respondToRoute'
    '$route.query.p': 'respondToRoute'
    '$route.query.k': 'respondToRoute'

  methods:
    init: ->
      Records.discussions.findOrFetchById(@$route.params.key, exclude_types: 'poll outcome')
      .then (discussion) =>
        window.location.host = discussion.group().newHost if discussion.group().newHost
        @discussion = discussion
        @loader = new ThreadLoader(@discussion)
        @respondToRoute()
        EventBus.$emit 'currentComponent',
          focusHeading: false
          page: 'threadPage'
          discussion: @discussion
          group: @discussion.group()
          title: @discussion.title

        @watchRecords
          key: 'strand'+@discussion.id
          collections: ['events']
          query: => @loader.updateCollection()
      .catch (error) ->
        EventBus.$emit 'pageError', error
        EventBus.$emit 'openAuthModal' if error.status == 403 && !Session.isSignedIn()

      # .catch (error) =>
      #   EventBus.$emit 'pageError', error
      #   EventBus.$emit 'openAuthModal' if error.status == 403 && !Session.isSignedIn()

    focusSelector: ->
      if @loader.focusAttrs.newest
        if @discussion.lastSequenceId()
          return ".sequenceId-#{@discussion.lastSequenceId()}"
        else
          return "#add-comment"

      if @loader.focusAttrs.unread
        if @loader.firstUnreadSequenceId()
          return ".sequenceId-#{@loader.firstUnreadSequenceId()}"
        else
          return '.context-panel'

      if @loader.focusAttrs.oldest
        return '.context-panel'

      if @loader.focusAttrs.commentId
        return "#comment-#{@loader.focusAttrs.commentId}"

      if @loader.focusAttrs.sequenceId
        return ".sequenceId-#{@loader.focusAttrs.sequenceId}"

      if @loader.focusAttrs.position
        return ".position-#{@loader.focusAttrs.position}"

      if @loader.focusAttrs.positionKey
        return ".positionKey-#{@loader.focusAttrs.positionKey}"

    scrollToFocusIfPresent: ->
      selector = @focusSelector()
      if document.querySelector(selector)
        @scrollTo(selector)
        @lastFocus = selector

    scrollToFocusUnlessFocused: ->
      selector = @focusSelector()
      unless @lastFocus == selector
        @scrollTo(selector)
        @lastFocus = selector

    elementInView: (el) ->
      rect = el.getBoundingClientRect()
      (rect.top >= 0 && rect.left >= 0 &&
       rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
       rect.right <= (window.innerWidth || document.documentElement.clientWidth))

    refocusIfOffscreen: ->
      if @lastFocus &&
         el = document.querySelector(@lastFocus) &&
         !@elementInView(el)
        console.log "refocusing #{@lastFocus}"
        @scrollTo(@lastFocus)

    respondToRoute: ->
      return unless @discussion
      return if @discussion.key != @$route.params.key
      return if @discussion.createdEvent.childCount == 0

      if @$route.query.k
        @loader.addLoadPositionKeyRule(@$route.query.k)
        @loader.focusAttrs = {positionKey: @$route.query.k}

      if @$route.query.p
        @loader.addLoadPositionRule(parseInt(@$route.params.p))
        @loader.focusAttrs = {position: @$route.query.p}

      if @$route.params.sequence_id
        @loader.addLoadSequenceIdRule(parseInt(@$route.params.sequence_id))
        @loader.focusAttrs = {sequenceId: parseInt(@$route.params.sequence_id)}

      if @$route.params.comment_id
        @loader.addLoadCommentRule(parseInt(@$route.params.comment_id))
        @loader.addLoadNewestRule()
        @loader.focusAttrs = {commentId: parseInt(@$route.params.comment_id)}

      if @loader.rules.length == 0
        if @discussion.newestFirst
          @loader.addLoadNewestRule()
          @loader.focusAttrs = {newest: 1}
        else
          if @discussion.lastReadAt
            if @discussion.unreadItemsCount() == 0
              @loader.addLoadNewestRule()
              @loader.focusAttrs = {newest: 1}
            else
              @loader.addLoadUnreadRule()
              @loader.focusAttrs = {unread: 1}
          else
            @loader.addLoadOldestRule()
            @loader.focusAttrs = {oldest: 1}

      @loader.addContextRule()

      @scrollToFocusIfPresent()

      @loader.fetch().finally =>
        setTimeout => @scrollToFocusUnlessFocused()

      .catch (res) =>
        console.log 'promises failed', res

</script>

<template lang="pug">
.strand-page
  v-main
    v-container.max-width-800(v-if="discussion")
      p(v-if="$route.query.debug" v-for="rule in loader.rules") {{rule}}
      //- p loader: {{loader.focusAttrs}}
      //- p ranges: {{discussion.ranges}}
      //- p read ranges: {{loader.readRanges}}
      //- p first unread {{loader.firstUnreadSequenceId()}}
      //- p test: {{rangeSetSelfTest()}}
      thread-current-poll-banner(:discussion="discussion")
      discussion-fork-actions(:discussion='discussion' :key="'fork-actions'+ discussion.id")
      discussion-template-banner(:discussion='discussion')

      strand-card(v-if="loader" :discussion='discussion' :loader="loader")
  strand-toc-nav(v-if="loader" :discussion="discussion" :loader="loader" :key="discussion.id")
</template>
