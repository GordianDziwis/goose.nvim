<? if current_file or mentioned_files or selections then ?>
  <additional-data>
    Below are some potentially helpful/relevant pieces of information for figuring out to respond. **IGNORE** if not relevant to user query.
    <? if current_file then ?>
      <current-file>
        Path: <%= current_file.relative_path %>
      </current-file>
    <? end ?>
    <? if selections or mentioned_files then ?>
      <attached-files>
        <? if selections then ?>
          <? for x, selection in ipairs(selections) do ?>
            <manually-added-selection>
              <? if selection.file then ?>
                ```<%= selection.file.extension %> <%= selection.file.name %> (lines <%= selection.lines %>)
                  <%= selection.content %>
                ```
              <? else ?>
                ```
                  <%= selection.content %>
                ```
              <? end ?>
            </manually-added-selection>
          <? end ?>
        <? end ?>
        <? if mentioned_files then ?>
          <? for x, path in ipairs(mentioned_files) do ?>
            <mentioned-file>
              Path: <%= path %>
            </mentioned-file>
          <? end ?>
        <? end ?>
      </attached-files>
    <? end ?>
  </additional-data>
  <user-query>
    <%= prompt %>
  </user-query>
<? else ?>
  <%= prompt %>
<? end ?>
