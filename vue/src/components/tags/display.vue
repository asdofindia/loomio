<script lang="coffee">
import Records from '@/shared/services/records'

export default
  props:
    tags: Array
    showCounts: Boolean
    smaller: Boolean
    selected: String

</script>
<template lang="pug">
span.tags-display
  v-chip.ml-1(
    :class="{'mb-1': showCounts}"
    v-for="tag in tags"
    :key="tag.id"
    :small="!smaller"
    :xSmall="smaller"
    :outlined="selected != tag.name"
    :color="tag.color"
    :to="'/g/'+tag.group().key+'/tags/'+tag.name"
    )
    span {{ tag.name }}
    span(v-if="showCounts")
      space
      span {{tag.taggingsCount}}
</template>
