<script lang="coffee">
import Records from '@/shared/services/records'
import Session from '@/shared/services/session'
import AppConfig from '@/shared/services/app_config'
import FileUploader from '@/shared/services/file_uploader'
import FilesList from './files_list.vue'
import EventBus from '@/shared/services/event_bus'
import I18n from '@/i18n'
import { convertToMd } from '@/shared/services/format_converter'

import Blockquote from '@tiptap/extension-blockquote'
import Bold from '@tiptap/extension-bold'
import BulletList from '@tiptap/extension-bullet-list'
import CodeBlock from '@tiptap/extension-code-block'
import Code from '@tiptap/extension-code'
import Document from '@tiptap/extension-document'
import Dropcursor from '@tiptap/extension-dropcursor'
import GapCursor from '@tiptap/extension-gapcursor'
import HardBreak from '@tiptap/extension-hard-break'
import Heading from '@tiptap/extension-heading'
import History from '@tiptap/extension-history'
import HorizontalRule from '@tiptap/extension-horizontal-rule'
import Italic from '@tiptap/extension-italic'
import Link from '@tiptap/extension-link'
import ListItem from '@tiptap/extension-list-item'
import OrderedList from '@tiptap/extension-ordered-list'
import Paragraph from '@tiptap/extension-paragraph'
import Placeholder from '@tiptap/extension-placeholder'
import Strike from '@tiptap/extension-strike'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import TableRow from '@tiptap/extension-table-row'
import Table from '@tiptap/extension-table'
# import TaskList from '@tiptap/extension-task-list'
import {CustomTaskItem} from './extension_custom_task_item'
import {CustomTaskList} from './extension_custom_task_list'
import TextStyle from '@tiptap/extension-text-style'
# import TextAlign from '@tiptap/extension-text-align'
import Text from '@tiptap/extension-text'
import Underline from '@tiptap/extension-underline'
import {CustomMention} from './extension_mention'
import {CustomImage} from './extension_image'
import {Iframe} from './extension_iframe'

import { Editor, EditorContent, VueRenderer } from '@tiptap/vue-2'

import {getEmbedLink} from '@/shared/helpers/embed_link.coffee'

import { CommonMentioning, HtmlMentioning, MentionPluginConfig } from './mentioning.coffee'
import SuggestionList from './suggestion_list'
import Attaching from './attaching.coffee'
import {compact, uniq, throttle, difference, reject, uniqBy} from 'lodash'
import TextHighlightBtn from './text_highlight_btn'
import TextAlignBtn from './text_align_btn'
import { TextAlign } from './extension_text_align'
import { Highlight } from './extension_highlight'

isValidHttpUrl = (string) ->
  url = undefined
  try
    url = new URL(string)
  catch _
    return false
  url.protocol == 'http:' or url.protocol == 'https:'

export default
  mixins: [CommonMentioning, HtmlMentioning, Attaching]
  props:
    model: Object
    field: String
    label: String
    placeholder: String
    maxLength: Number
    shouldReset: Boolean
    autofocus: Boolean

  components: {
    EditorContent
    TextAlignBtn
    TextHighlightBtn
    SuggestionList
    FilesList
  }

  data: ->
    loading: true
    socket: null
    count: 0
    editor: null
    expanded: false
    closeEmojiMenu: false
    linkUrl: ""
    iframeUrl: ""
    linkDialogIsOpen: false
    iframeDialogIsOpen: false
    fetchedUrls: []

  computed:
    format: ->
      @model["#{@field}Format"]

  mounted: ->
    @expanded = Session.user().experiences['html-editor.expanded']
    @model.beforeSave = => @updateModel()
    @editor = new Editor
      editorProps:
        scrollThreshold: 100
        scrollMargin: 100
      autofocus: @autofocus
      extensions: [
        Blockquote
        Bold
        BulletList
        CodeBlock
        CustomImage.configure({attachFile: @attachFile, attachImageFile: @attachImageFile})
        Document
        Dropcursor
        GapCursor
        Heading
        Highlight.configure({ multicolor: true })
        History
        HorizontalRule
        Italic
        Iframe
        Link
        ListItem
        OrderedList
        Paragraph
        Placeholder.configure(placeholder: @placeholder)
        Strike
        Text
        Table
        TableHeader
        TableRow
        TableCell
        CustomTaskList
        CustomTaskItem
        CustomMention.configure(MentionPluginConfig.bind(@)())
        TextStyle
        TextAlign.configure({ types: ['heading', 'paragraph'] })
        Underline
      ]
      content: @model[@field]
      onUpdate: =>
        @checkLength() if @maxLength
        @scrapeLinkPreviews() if @model.isNew()

  watch:
    'shouldReset': 'reset'

  methods:
    checkLength: ->
      @model.saveDisabled = @editor.getCharacterCount() > @maxLength

    setCount: (count) ->
      @count = count

    tiptapAddress: ->
      if @model.isNew()
        compact([AppConfig.theme.channels_uri, 'tiptap', @model.constructor.singular, 'new', @model.groupId, @model.discussionId, @model.parentId, Session.user().secretToken]).join('/')
      else
        [AppConfig.theme.channels_uri, 'tiptap', @model.constructor.singular, @model.id, (@model.secretToken || Session.user().secretToken)].join('/')

    selectedText: ->
      state = @editor.state
      selection = @editor.state.selection
      { from, to } = selection
      state.doc.textBetween(from, to, ' ')

    reset: ->
      @editor.chain().clearContent().run()
      @resetFiles()
      @model.beforeSave = => @updateModel()

    convertToMd: ->
      if confirm I18n.t('formatting.markdown_confirm')
        @updateModel()
        convertToMd(@model, @field)
        Records.users.saveExperience('html-editor.uses-markdown')

    toggleExpanded: ->
      @expanded = !@expanded
      Records.users.saveExperience('html-editor.expanded', @expanded)

    setLinkUrl: ->
      if @linkUrl
        @linkUrl = "http://".concat(@linkUrl) unless @linkUrl.includes("://")
        @editor.chain().setLink(href: @linkUrl).focus().run()
        @fetchLinkPreviews([@linkUrl])
        @linkUrl = null
      @linkDialogIsOpen = false

    setIframeUrl: () ->
      return unless isValidHttpUrl(@iframeUrl)
      @editor.chain().setIframe(src: getEmbedLink(@iframeUrl)).focus().run()
      @iframeUrl = null
      @iframeDialogIsOpen = false

    emojiPicked: (shortcode, unicode) ->
      @editor.chain()
          .insertContent(unicode)
          .focus()
          .run()
      @closeEmojiMenu = false

    updateModel: ->
      return unless @format == 'html'
      @model[@field] = @editor.getHTML()
      @model[@field] = '' if @model[@field] == '<p></p>'
      @updateFiles()

    removeLinkPreview: (url) ->
      @model.linkPreviews = reject(@model.linkPreviews, (p) -> p.url == url)

    scrapeLinkPreviews: throttle ->
      parser = new DOMParser()
      doc = parser.parseFromString(@editor.getHTML(), 'text/html')
      @fetchLinkPreviews difference((Array.from(doc.querySelectorAll('a')).map (el) => el.href), @fetchedUrls)
    ,
      500
    ,
      {leading: false}

    fetchLinkPreviews: (urls) ->
      if urls.length
        @fetchedUrls = uniq @fetchedUrls.concat(urls)
        Records.remote.post('link_previews', {urls: urls}).then (data) =>
          @model.linkPreviews = uniqBy(@model.linkPreviews.concat(data.previews), 'url')

  beforeDestroy: ->
    @editor.destroy() if @editor
    # @socket.close() if @socket

</script>

<template lang="pug">
div
  //- template(v-if="!editor || loading")
  //-   | Connecting to socket server …
  .editor.mb-3(v-if="editor")
    editor-content.html-editor__textarea(ref="editor" :editor='editor').lmo-markdown-wrapper
    .menubar
      div
        v-layout(align-center v-if="editor.isActive('table')")
          v-btn(icon @click="editor.chain().deleteTable().focus().run()" :title="$t('formatting.remove_table')")
            v-icon mdi-table-remove
          v-btn(icon @click="editor.chain().addColumnBefore().focus().run()" :title="$t('formatting.add_column_before')")
            v-icon mdi-table-column-plus-before
          v-btn(icon @click="editor.chain().addColumnAfter().focus().run()" :title="$t('formatting.add_column_after')")
            v-icon mdi-table-column-plus-after
          v-btn(icon @click="editor.chain().deleteColumn().focus().run()" :title="$t('formatting.remove_column')")
            v-icon mdi-table-column-remove
          v-btn(icon @click="editor.chain().addRowBefore().focus().run()" :title="$t('formatting.add_row_before')")
            v-icon mdi-table-row-plus-before
          v-btn(icon @click="editor.chain().addRowAfter().focus().run()" :title="$t('formatting.add_row_after')")
            v-icon mdi-table-row-plus-after
          v-btn(icon @click="editor.chain().deleteRow().focus().run()" :title="$t('formatting.remove_row')")
            v-icon mdi-table-row-remove
          v-btn(icon @click="editor.chain().mergeOrSplit().focus().run()" :title="$t('formatting.merge_selected')")
            v-icon mdi-table-merge-cells

        v-layout.py-2.justify-space-between.flex-wrap(align-center)
          section.d-flex.flex-wrap(:aria-label="$t('formatting.formatting_tools')")
            //- attach
            v-btn(icon @click='$refs.filesField.click()' :title="$t('formatting.attach')")
              v-icon mdi-paperclip

            v-btn(icon @click='$refs.imagesField.click()' :title="$t('formatting.insert_image')")
              v-icon mdi-image

            //- link
            v-menu(:close-on-content-click="!selectedText()" v-model="linkDialogIsOpen" min-width="320px")
              template(v-slot:activator="{on, attrs}")
                template(v-if="editor.isActive('link')")
                  v-btn(icon @click="editor.chain().toggleLink().focus().run()" outlined :title="$t('formatting.link')")
                    v-icon mdi-link-variant
                template(v-else)
                  v-btn(icon v-on="on" v-bind="attrs" :title="$t('formatting.link')")
                    v-icon mdi-link-variant
              v-card
                template(v-if="selectedText()")
                  v-card-title.title(v-t="'text_editor.insert_link'")
                  v-card-text
                    v-text-field(type="url" label="https://www.example.com" v-model="linkUrl" autofocus ref="focus" v-on:keyup.enter="setLinkUrl()")
                  v-card-actions
                    v-spacer
                    v-btn(color="primary" @click="setLinkUrl()" v-t="'common.action.apply'")
                template(v-else)
                  v-card-title(v-t="'text_editor.select_text_to_link'")

            //- emoji
            v-menu(:close-on-content-click="false" v-model="closeEmojiMenu")
              template(v-slot:activator="{on, attrs}")
                v-btn.emoji-picker__toggle(v-on="on" v-bind="attrs" icon :title="$t('formatting.insert_emoji')")
                  v-icon mdi-emoticon-outline
              emoji-picker(:insert="emojiPicked")

            template(v-if="expanded")
              //- v-btn(icon @click='editor.chain().focus().setParagraph().run()' :outlined="editor.isActive('paragraph')" :title="$t('formatting.paragraph')")
              //-   v-icon mdi-format-pilcrow
              template(v-for="i in [2,3]")
                v-btn(icon @click='editor.chain().focus().toggleHeading({ level: i }).run()' :outlined="editor.isActive('heading', { level: i })" :title="$t('formatting.heading'+i)")
                  v-icon {{'mdi-format-header-'+i}}

            //- bold
            v-btn(icon v-if="expanded" @click='editor.chain().toggleBold().focus().run()' :outlined="editor.isActive('bold')" :title="$t('formatting.bold')")
              v-icon mdi-format-bold

            //- italic
            v-btn(icon v-if="expanded" @click='editor.chain().toggleItalic().focus().run()' :outlined="editor.isActive('italic')" :title="$t('formatting.italicize')")
              v-icon mdi-format-italic
            //-
            //- //- strikethrough
            //- v-btn(icon v-if="expanded" @click='editor.chain().toggleStrike().focus().run()' :outlined="editor.isActive('strike')"  :title="$t('formatting.strikethrough')")
            //-   v-icon mdi-format-strikethrough
            //- underline
            //- v-btn(icon v-if="expanded" @click='editor.chain().toggleUnderline().focus().run()' :outlined="editor.isActive('underline')",  :title="$t('formatting.underline')")
            //-   v-icon mdi-format-underline
            //-

            v-btn(icon v-if="expanded" @click='editor.chain().toggleBulletList().focus().run()' :outlined="editor.isActive('bulletList')"  :title="$t('formatting.bullet_list')")
              v-icon mdi-format-list-bulleted
            v-btn(icon v-if="expanded" @click='editor.chain().toggleOrderedList().focus().run()' :outlined="editor.isActive('orderedList')"  :title="$t('formatting.number_list')")
              v-icon mdi-format-list-numbered
            v-btn(icon v-if="expanded" @click='editor.chain().toggleTaskList().focus().run()' :outlined="editor.isActive('taskList')"  :title="$t('formatting.task_list')")
              v-icon mdi-checkbox-marked-outline

            text-highlight-btn(v-if="expanded" :editor="editor")
            text-align-btn(v-if="expanded" :editor="editor")

            //- extra text marks
            template(v-if="expanded")
              //- strikethrough
              v-menu(:close-on-content-click="false" v-model="iframeDialogIsOpen" min-width="320px")
                template(v-slot:activator="{on}")
                  v-btn(icon v-on="on" :title="$t('formatting.embed')")
                    v-icon mdi-youtube
                v-card
                  v-card-title.title(v-t="'text_editor.insert_embedded_url'")
                  v-card-text
                    v-text-field(type="url" label="e.g. https://www.youtube.com/watch?v=Zlzuqsunpxc" v-model="iframeUrl" ref="focus" autofocus v-on:keyup.enter="setIframeUrl()")
                  v-card-actions
                    v-spacer
                    v-btn(color="primary" @click="setIframeUrl()" v-t="'common.action.apply'")
              //- blockquote
              v-btn(icon @click='editor.chain().toggleBlockquote().focus().run()' :outlined="editor.isActive('blockquote')"  :title="$t('formatting.blockquote')")
                v-icon mdi-format-quote-close
              //- //- code block
              v-btn(icon @click='editor.chain().toggleCodeBlock().focus().run()' :outlined="editor.isActive('codeBlock')"  :title="$t('formatting.code_block')")
                v-icon mdi-code-braces
              //- embded
              v-btn(icon @click='editor.chain().setHorizontalRule().focus().run()'  :title="$t('formatting.divider')")
                v-icon mdi-minus
              //- table
              v-btn(icon @click='editor.chain().insertTable({rows: 3, cols: 3, withHeaderRow: false }).focus().run()' :title="$t('formatting.add_table')" :outlined="editor.isActive('table')")
                v-icon mdi-table
              //- markdown (save experience)
              v-btn(icon @click="convertToMd" :title="$t('formatting.edit_markdown')")
                v-icon mdi-language-markdown-outline

            v-btn.html-editor__expand(v-if="!expanded" icon @click="toggleExpanded" :title="$t('formatting.expand')")
              v-icon mdi-chevron-right

            v-btn.html-editor__expand(v-if="expanded" icon @click="toggleExpanded" :title="$t('formatting.collapse')")
              v-icon mdi-chevron-left
          //- save button?
          v-spacer
          slot(v-if="!expanded" name="actions")
    div.d-flex(v-if="expanded" name="actions")
      v-spacer
      slot(name="actions")

    v-alert.text-right(dense v-if="maxLength" :color='((maxLength < editor.getCharacterCount()) && "error" ) || ""')
      span(v-t="{path: 'text_editor.x_of_y_characters', args: {x: editor.getCharacterCount(), y: maxLength}}")

  link-previews(:model="model" :remove="removeLinkPreview")
  suggestion-list(:query="query" :loading="fetchingMentions" :mentionable="mentionable" :positionStyles="suggestionListStyles" :navigatedUserIndex="navigatedUserIndex" @select-user="selectUser")
  files-list(:files="files" v-on:removeFile="removeFile")

  form(style="display: block" @change="fileSelected")
    input(ref="filesField" type="file" name="files" multiple=true)

  form(style="display: block" @change="imageSelected")
    input(ref="imagesField" type="file" name="files" multiple=true)
</template>
<style lang="sass">

.ProseMirror-widget
  position: absolute
  width: 0.1px
  /*border-style: solid;*/

.bv-row
  padding-top: 20px

.ProseMirror [contenteditable="false"]
  white-space: normal

.ProseMirror [contenteditable="true"]
  white-space: pre-wrap

// .ProseMirror
//   > * + *
//     margin-top: 0.75em

/* Placeholder (at the top) */
.ProseMirror p.is-editor-empty:first-child::before
  content: attr(data-placeholder)
  float: left
  color: #ced4da
  pointer-events: none
  height: 0

.ProseMirror
  outline: none
  min-height: 64px

progress
  width: 50%!important
  -webkit-appearance: none
  appearance: none
  background-color: #fff
  border: 1px solid #ccc
progress::-webkit-progress-bar
  background-color: #fff
  border: 1px solid #ccc
progress::-webkit-progress-value
  background-color: lightblue
  border: 0
  transition: width 120ms ease-out, opacity 60ms 60ms ease-in
progress::-moz-progress-bar
  background-color: lightblue
  border: 0
  transition: width 120ms ease-out, opacity 60ms 60ms ease-in

.menubar
  position: sticky
  bottom: 0

.menubar
  .drop-down-button
    width: 40px !important
  .menu-down-arrow
    margin-left: -10px
  .v-btn--icon
    width: 32px
    height: 32px

  .v-btn.v-btn--icon
    min-width: 0
    margin-left: 0
    margin-right: 0
    max-width: 32px
    .v-icon
      font-size: 16px

.html-editor__textarea .ProseMirror
  border-bottom: 1px solid #999
  padding: 4px 0px
  margin: 4px 0px
  outline: none
  overflow-y: scroll
  overflow: visible

.html-editor__textarea .ProseMirror:focus
  border-bottom: 1px solid var(--v-primary-base)


// .lmo-textarea p.is-empty:first-child::before
//   content: attr(data-empty-text)
//   float: left
//   color: #aaa
//   pointer-events: none
//   height: 0
//
// .lmo-textarea p.is-empty
//   font-size: 16px
//   padding-bottom: 16px

ul[data-type="todo_list"]
  padding-left: 0

li[data-type="todo_item"]
  display: flex
  flex-direction: row

.todo-checkbox
  border: 1px solid #999
  height: 1.3em
  width: 1.3em
  box-sizing: border-box
  margin-right: 8px
  margin-top: 0px
  user-select: none
  border-radius: 0.2em
  background-color: transparent
  &:hover
    border: 1px solid var(--v-primary-base)
    // background: #eee

.lmo-textarea .todo-checkbox
  cursor: pointer

.todo-content
  flex: 1
  > p:last-of-type
    margin-bottom: 0
  > ul[data-type="todo_list"]
    margin: .5rem 0
  p
    margin: 0

li[data-done="true"]
  > .todo-content
    > p
      text-decoration: line-through
  > .todo-checkbox::before
    position: relative
    top: -6px
    color: var(--v-accent-base)
    font-size: 1.5rem
    content: "✓"

li[data-done="false"]
  text-decoration: none

input[type="file"]
  display: none

// .html-editor__textarea, .formatted-text
.lmo-markdown-wrapper
  div[data-iframe-container], .iframe-container
    position: relative
    padding-bottom: 100/16*9%
    height: 0
    overflow: hidden
    width: 100%
    height: auto
    &.ProseMirror-selectednode
      outline: 3px solid #68CEF8
    iframe
      border: 0
      position: absolute
      top: 0
      left: 0
      width: 100%
      height: 100%
      outline: 2px solid #68CEF8

</style>
