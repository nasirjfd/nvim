;; extends

; A string on its own at the top of the document (not inside an object or array) gets the string
; colour too. The values a Kulala `css …::text` filter takes out of a response are listed this way.
(document
  (string) @string)

; Concealing is only on in Kulala's response window (conceallevel 0 elsewhere). There the base query
; draws \" inside a string as a plain " but also hides the quotes around every string; keep those
; quotes on screen (drawn as themselves, above the base rule). The window links Conceal to String.
("\"" @conceal
  (#set! conceal "\"")
  (#set! priority 110))
