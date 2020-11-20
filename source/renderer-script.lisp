;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :nyxt)

(export-always 'define-parenscript)
(defmacro define-parenscript (script-name args &body script-body)
  "Define parenscript function SCRIPT-NAME.
SCRIPT-BODY must be a valid parenscript and will be wrapped in (PS:PS ...).
Any Lisp expression must be wrapped in (PS:LISP ...).

The returned function sends the compiled Javascript to the current buffer webview.
The function can be passed ARGS."
  `(progn
     (defun ,script-name ,args
       (ffi-buffer-evaluate-javascript (current-buffer)
                                       (ps:ps ,@script-body)))))

(export-always 'pflet)
(defmacro pflet (((function function-arguments &body function-body)) &body body)
  "Define single parenscript function in a flet body."
  `(flet ((,function ,function-arguments
            (ffi-buffer-evaluate-javascript-async (current-buffer)
                                            (ps:ps ,@function-body))))
     ,@body))

;; TODO: after implementing reader-view, utilize reader-view algorithm
;; to get only document data ignoring images, css, etc
(define-parenscript document-get-body (&key (limit 100000))
  (ps:chain document body |innerHTML| (slice 0 (ps:lisp limit))))

(define-parenscript document-get-paragraph-contents (&key (limit 100000))
  (defun qsa (context selector)
    (ps:chain context (query-selector-all selector)))
  (let ((result ""))
    (loop for element in (qsa document (list "p"))
          do (setf result (+ result
                             (ps:chain element text-content))))
    (ps:chain result (slice 0 (ps:lisp limit)))))

(export-always '%paste)
(define-parenscript %paste (&key (input-text (ring-insert-clipboard (clipboard-ring *browser*))))
  (let ((active-element (ps:chain document active-element))
        (tag (ps:chain document active-element tag-name)))
    (when (or (string= tag "INPUT")
              (string= tag "TEXTAREA"))
      (let ((start-position (ps:chain active-element selection-start))
            (end-position (ps:chain active-element selection-end)))
        (setf (ps:chain active-element value)
              (+ (ps:chain active-element value (substring 0 start-position))
                 (ps:lisp input-text)
                 (ps:chain active-element value
                           (substring end-position
                                      (ps:chain active-element value length)))))))))

(export-always '%copy)
(define-parenscript %copy ()
  "Return selected text from javascript."
  (ps:chain window (get-selection) (to-string)))

(defun html-write (content &optional (buffer (current-buffer)))
  (ffi-buffer-evaluate-javascript-async
   buffer
   (ps:ps (ps:chain document
                    (write (ps:lisp content))))))

(defun html-set (content &optional (buffer (current-buffer)))
  (ffi-buffer-evaluate-javascript-async
   buffer
   (ps:ps (setf (ps:@ document body |innerHTML|)
                (ps:lisp content)))))

(defun html-set-style (style-string &optional (buffer (current-buffer)))
  (let ((style (markup:markup (:style style-string))))
    (ffi-buffer-evaluate-javascript-async
     buffer
     (ps:ps (ps:chain document body
                      (|insertAdjacentHTML| "afterbegin"
                                            (ps:lisp style)))))))

(defmacro with-current-html-buffer ((buffer-var title mode) &body body)
  "Switch to a buffer in MODE displaying CONTENT.
If a buffer in MODE with TITLE exists, reuse it, otherwise create a new buffer.
BUFFER-VAR is bound to the new bufer in BODY.
MODE is a mode symbol.
BODY must return the HTML markup as a string."
  `(let* ((,buffer-var (or (find-if (lambda (b)
                                      (and (string= (title b) ,title)
                                           (find-mode b ,mode)))
                                    (buffer-list))
                           (funcall (symbol-function ,mode)
                                    :activate t
                                    :buffer (make-internal-buffer :title ,title)))))
     (html-set
      (progn
        ,@body)
      ,buffer-var)
     (set-current-buffer ,buffer-var)
     ,buffer-var))
