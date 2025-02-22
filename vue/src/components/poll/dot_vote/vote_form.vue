<script lang="coffee">
import Records  from '@/shared/services/records'
import EventBus from '@/shared/services/event_bus'
import Flash   from '@/shared/services/flash'
import { sum, map, head, filter, without, sortBy, isEqual } from 'lodash'

export default
  props:
    stance: Object

  data: ->
    pollOptions: []
    stanceChoices: []

  created: ->
    @watchRecords
      collections: ['pollOptions']
      query: (records) =>
        if @stance.poll().optionsDiffer(@pollOptions)
          @pollOptions = @stance.poll().pollOptionsForVoting()
          @stanceChoices = map @pollOptions, (option) =>
            option: option
            score: @stance.scoreFor(option)

  methods:
    submit: ->
      if sum(map(@stanceChoices, 'score')) > 0
        @stance.stanceChoicesAttributes = map @stanceChoices, (choice) =>
          poll_option_id: choice.option.id
          score: choice.score
      actionName = if !@stance.castAt then 'created' else 'updated'
      @stance.save()
      .then =>
        Flash.success "poll_#{@stance.poll().pollType}_vote_form.stance_#{actionName}"
        EventBus.$emit "closeModal"
      .catch => true

    rulesForChoice: (choice) ->
      [(v) => (v <= @maxForChoice(choice)) || @$t('poll_dot_vote_vote_form.too_many_dots')]

    percentageFor: (choice) ->
      max = dotsPerPerson
      return unless max > 0
      "#{100 * choice.score / max}% 100%"

    backgroundImageFor: (option) ->
      "url(/img/poll_backgrounds/#{option.color.replace('#','')}.png)"

    styleData: (choice) ->
      'border-color': choice.option.color
      'background-image': @backgroundImageFor(choice.option)
      'background-size': @percentageFor(choice)

    adjust: (choice, amount) ->
      choice.score += amount

    maxForChoice: (choice) ->
      @dotsPerPerson - sum(map(without(@stanceChoices, choice), 'score'))

  computed:
    dotsRemaining: ->
      @dotsPerPerson - sum(map(@stanceChoices, 'score'))

    dotsPerPerson: ->
      @stance.poll().customFields.dots_per_person
    reasonTooLong: ->
      !@stance.poll().allowLongReason && @stance.reason && @stance.reason.length > 500


</script>

<template lang="pug">
.poll-dot-vote-vote-form
  v-subheader.poll-dot-vote-vote-form__dots-remaining(v-t="{ path: 'poll_dot_vote_vote_form.dots_remaining', args: { count: dotsRemaining } }")
  .poll-dot-vote-vote-form__options
    .poll-dot-vote-vote-form__option(v-for='choice in stanceChoices', :key='choice.option.id')
      v-subheader.poll-dot-vote-vote-form__option-label {{ choice.option.name }}
      v-layout(row align-center)
        v-slider.poll-dot-vote-vote-form__slider.mr-4(
          v-model='choice.score'
          :rules="rulesForChoice(choice)"
          :color="choice.option.color"
          :thumb-color="choice.option.color"
          :track-color="choice.option.color"
          :height="4"
          :thumb-size="24"
          :thumb-label="(choice.score > 0) ? 'always' : true"
          :min="0"
          :max="dotsPerPerson"
          :readonly="false")
    validation-errors(:subject='stance', field='stanceChoices')

  poll-common-add-option-button(:poll='stance.poll()')
  poll-common-stance-reason(:stance='stance')
  v-card-actions.poll-common-form-actions
    v-spacer
    v-btn.poll-common-vote-form__submit(color="primary" :disabled="(dotsRemaining < 0)" :loading="stance.processing" @click="submit()")
      span(v-t="stance.castAt? 'poll_common.update_vote' : 'poll_common.submit_vote'")
</template>
