-- Fixed AppleScriptObjC helper; invoked explicitly with -l AppleScript.
-- Input is JSON jsonData in argv; never interpolate caller text into executable code.
use framework "Foundation"
use framework "AppKit"
use scripting additions

on obj(keys, vals)
  return current application's NSDictionary's dictionaryWithObjects:vals forKeys:keys
end obj
on encode(value)
  set jsonData to current application's NSJSONSerialization's dataWithJSONObject:value options:0 |error|:(missing value)
  if jsonData is missing value then error "JSON serialization failed"
  set nsText to current application's NSString's alloc()
  return (nsText's initWithData:jsonData encoding:4) as text
end encode
on canonical(mb)
  using terms from application "Mail"
    tell application "Mail"
      set canonicalName to name of mb
      set parentBox to missing value
      try
        set parentBox to container of mb
      end try
      repeat with depth from 1 to 100
        if parentBox is missing value then return canonicalName
        set parentClass to missing value
        try
          set parentClass to class of parentBox
        end try
        if parentClass is not mailbox and parentClass is not container then return canonicalName
        set canonicalName to (name of parentBox) & "/" & canonicalName
        set parentBox to container of parentBox
      end repeat
    end tell
  end using terms from
  error "Mailbox nesting exceeds safe bound"
end canonical
on findAccount(accountName)
  tell application "Mail"
    set matches to accounts whose name is accountName
    if (count of matches) is not 1 then error "Account is missing or ambiguous"
    return item 1 of matches
  end tell
end findAccount
on findBox(acct, boxName)
  set found to {}
  set oldDelimiters to AppleScript's text item delimiters
  set AppleScript's text item delimiters to "/"
  set leafName to last text item of boxName
  set AppleScript's text item delimiters to oldDelimiters
  tell application "Mail" to set candidates to mailboxes of acct whose name is leafName
  repeat with candidate in candidates
    if my canonical(contents of candidate) is boxName then set end of found to contents of candidate
  end repeat
  if (count of found) is not 1 then error "Mailbox is missing or ambiguous"
  return item 1 of found
end findBox
on numericText(n)
  -- NSNumber avoids AppleScript scientific notation for large Mail identifiers.
  return (current application's NSNumber's numberWithDouble:n)'s stringValue() as text
end numericText
on dateText(received)
  set parts to current application's NSDateComponents's new()
  parts's setYear:(year of received)
  parts's setMonth:((month of received) as integer)
  parts's setDay:(day of received)
  parts's setHour:(hours of received)
  parts's setMinute:(minutes of received)
  parts's setSecond:(seconds of received)
  set cal to current application's NSCalendar's calendarWithIdentifier:"gregorian"
  cal's setTimeZone:(current application's NSTimeZone's localTimeZone())
  set nativeDate to cal's dateFromComponents:parts
  if nativeDate is missing value then error "Invalid received date"
  set formatter to current application's NSISO8601DateFormatter's new()
  set resultText to formatter's stringFromDate:nativeDate
  if resultText is missing value then error "Date serialization failed"
  return resultText as text
end dateText
on messageRecord(msg, includeBody)
  -- One scoped AppleEvent returns a record; extracting its fields is local.
  -- Keep exactMessage's account/mailbox/ID resolution unchanged.
  tell application "Mail" to set props to properties of msg
  using terms from application "Mail"
    set mid to my numericText(id of props)
    set subj to subject of props as text
    set snd to sender of props as text
    set received to date received of props
    set flagged to flagged status of props
    set stableID to message id of props as text
    set txt to ""
    if includeBody then set txt to content of props as text
  end using terms from
  set receivedText to my dateText(received)
  return my obj({"id", "subject", "sender", "dateReceived", "isFlagged", "body", "rfcMessageId", "messageId"}, {mid, subj, snd, receivedText, flagged, txt, stableID, stableID})
end messageRecord
on exactMessage(box, wanted)
  tell application "Mail"
    set hits to messages of box whose id is wanted
    if (count of hits) is not 1 then error "Message is missing or ambiguous in explicit scope"
    return item 1 of hits
  end tell
end exactMessage
on perform(p)
  set runningApps to current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:"com.apple.mail"
  if (runningApps's |count|() as integer) is 0 then error "Apple Mail must already be running"
  set operation to (p's objectForKey:"operation") as text
  if operation is "accounts" then
    set rows to {}
    tell application "Mail" to set accountRefs to accounts
    repeat with a in accountRefs
      tell application "Mail"
        set accountName to name of a
        set addresses to email addresses of a
      end tell
      set end of rows to my obj({"name", "emailAddresses"}, {accountName, addresses})
    end repeat
    return my obj({"ok", "accounts"}, {true, rows})
  end if
  set acct to my findAccount((p's objectForKey:"account") as text)
  if operation is "mailboxes" then
    set rows to {}
    tell application "Mail" to set boxes to mailboxes of acct
    repeat with b in boxes
      set boxName to my canonical(contents of b)
      set end of rows to my obj({"name"}, {boxName})
    end repeat
    return my obj({"ok", "mailboxes"}, {true, rows})
  end if
  set box to my findBox(acct, (p's objectForKey:"mailbox") as text)
  if operation is "read" or operation is "move" then
    set wantedIDs to (p's objectForKey:"ids") as list
    if (count of wantedIDs) < 1 or (count of wantedIDs) > 100 then error "Invalid batch size"
    set refs to {}
    repeat with wanted in wantedIDs
      set end of refs to my exactMessage(box, wanted as real)
    end repeat
    if operation is "read" then
      set rows to {}
      repeat with msg in refs
        set end of rows to my messageRecord(contents of msg, true)
      end repeat
      return my obj({"ok", "messages"}, {true, rows})
    end if
    set destination to my findBox(acct, (p's objectForKey:"destination") as text)
    repeat with msg in refs
      tell application "Mail" to move (contents of msg) to destination
    end repeat
    return my obj({"ok", "success", "failed"}, {true, count of refs, 0})
  end if
  tell application "Mail" to set total to count of messages of box
  set rows to {}
  if operation is "identities" then
    if total > 100000 then error "Identity snapshot exceeds safe bound"
    tell application "Mail"
      set numericIDs to id of messages of box
      set stableIDs to message id of messages of box
      set idsAfter to id of messages of box
      set afterCount to count of messages of box
    end tell
    if class of numericIDs is not list then set numericIDs to {numericIDs}
    if class of stableIDs is not list then set stableIDs to {stableIDs}
    if class of idsAfter is not list then set idsAfter to {idsAfter}
    if numericIDs is not idsAfter or afterCount is not total then error "Mailbox changed during identity projection"
    if (count of numericIDs) is not total or (count of stableIDs) is not total then error "Incomplete identity page"
    return my obj({"ok", "ids", "rfcs", "count", "complete"}, {true, numericIDs, stableIDs, total, true})
  end if
  if operation is "list" then
    set offset to (p's objectForKey:"offset") as integer
    set limit to (p's objectForKey:"limit") as integer
    set lastIndex to offset + limit
    if lastIndex > total then set lastIndex to total
    if offset < total then
      set firstIndex to offset + 1
      tell application "Mail"
        set pageIDs to id of messages firstIndex thru lastIndex of box
        set pageSubjects to subject of messages firstIndex thru lastIndex of box
        set pageSenders to sender of messages firstIndex thru lastIndex of box
        set pageDates to date received of messages firstIndex thru lastIndex of box
        set pageFlags to flagged status of messages firstIndex thru lastIndex of box
        set pageRFCs to message id of messages firstIndex thru lastIndex of box
        set pageIDsAfter to id of messages firstIndex thru lastIndex of box
      end tell
      if pageIDs is not pageIDsAfter then error "Mailbox changed during header projection"
      if class of pageIDs is not list then set pageIDs to {pageIDs}
      if class of pageSubjects is not list then set pageSubjects to {pageSubjects}
      if class of pageSenders is not list then set pageSenders to {pageSenders}
      if class of pageDates is not list then set pageDates to {pageDates}
      if class of pageFlags is not list then set pageFlags to {pageFlags}
      if class of pageRFCs is not list then set pageRFCs to {pageRFCs}
      set expected to lastIndex - firstIndex + 1
      repeat with projection in {pageIDs, pageSubjects, pageSenders, pageDates, pageFlags, pageRFCs}
        if (count of projection) is not expected then error "Incomplete header projection"
      end repeat
      set formatter to current application's NSISO8601DateFormatter's new()
      repeat with i from 1 to expected
        set receivedText to my dateText(item i of pageDates)
        set end of rows to my obj({"id", "subject", "sender", "dateReceived", "isFlagged", "messageId"}, {my numericText(item i of pageIDs), item i of pageSubjects, item i of pageSenders, receivedText, item i of pageFlags, item i of pageRFCs})
      end repeat
    end if
    tell application "Mail" to if (count of messages of box) is not total then error "Mailbox changed during listing"
    return my obj({"ok", "messages", "hasMore"}, {true, rows, lastIndex < total})
  end if
  error "Unsupported native operation"
end perform
on run argv
  try
    if (count of argv) is not 1 then error "Expected one JSON input"
    set raw to current application's NSString's stringWithString:(item 1 of argv)
    set jsonData to raw's dataUsingEncoding:4
    set p to current application's NSJSONSerialization's JSONObjectWithData:jsonData options:0 |error|:(missing value)
    if p is missing value then error "Invalid JSON input"
    return my encode(my perform(p))
  on error msg number n
    set safeErrors to {"Identity snapshot exceeds safe bound", "JSON serialization failed", "Mailbox nesting exceeds safe bound", "Account is missing or ambiguous", "Mailbox is missing or ambiguous", "Invalid received date", "Date serialization failed", "Message is missing or ambiguous in explicit scope", "Apple Mail must already be running", "Invalid batch size", "Mailbox changed during identity projection", "Incomplete identity page", "Mailbox changed during identity snapshot", "Mailbox count is incomplete", "Mailbox changed during header projection", "Incomplete header projection", "Mailbox changed during listing", "Unsupported native operation", "Expected one JSON input", "Invalid JSON input"}
    set summary to "Native Mail operation failed (" & n & ")"
    if msg is in safeErrors then set summary to summary & ": " & msg
    return my encode(my obj({"ok", "error", "errorCode"}, {false, summary, n}))
  end try
end run
