<script lang="coffee">
import svg from 'svg.js'
import AppConfig from '@/shared/services/app_config'
import { each, max, sum } from 'lodash'

export default
  props:
    size: Number
    poll: Object
  data: ->
    svgEl: null
  methods:
    draw: ->
      y = 0
      each @stanceCounts, (count, index) =>
        height = (@size * max([parseInt(count), 0])) / @poll.votersCount
        @svgEl.rect(@size, height)
            .fill(AppConfig.pollColors.count[index])
            .x(0)
            .y(@size - height - y)
        y += height

      @svgEl.circle(@size / 2)
          .fill("#fff")
          .x(@size / 4)
          .y(@size / 4)
      @svgEl.text((sum(@stanceCounts) || 0).toString())
          .font(size: @fontSize, anchor: 'middle')
          .x(@size / 2)
          .y((@size / 4) + 3)
  watch:
    'poll.stanceCounts': -> @draw()

  computed:
    fontSize: -> @size * 0.33
    stanceCounts: -> @poll.stanceCounts

  mounted: ->
    @svgEl = svg(@$refs.svg).size('100%', '100%')
    @draw()

</script>

<template lang="pug">
div(ref="svg" :style="{width: size+'px', height: size+'px'}" class="progress-chart")
</template>
<style lang="sass">
.progress-chart
	background-color: #ccc

</style>
