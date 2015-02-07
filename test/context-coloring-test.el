;;; test/context-coloring-test.el --- Tests for context coloring. -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2015  Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

;;; Test running utilities

(defconst context-coloring-test-path
  (file-name-directory (or load-file-name buffer-file-name))
  "This file's directory.")

(defun context-coloring-test-read-file (path)
  "Read a file's contents into a string."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path context-coloring-test-path))
    (buffer-string)))

(defun context-coloring-test-setup ()
  "Preparation code to run before all tests."
  (setq context-coloring-comments-and-strings nil))

(defun context-coloring-test-cleanup ()
  "Cleanup code to run after all tests."
  (setq context-coloring-comments-and-strings t)
  (setq context-coloring-after-colorize-hook nil)
  (setq context-coloring-js-block-scopes nil)
  (context-coloring-set-colors-default))

(defmacro context-coloring-test-with-fixture (fixture &rest body)
  "Evaluate BODY in a temporary buffer with the relative
FIXTURE."
  `(with-temp-buffer
     (unwind-protect
         (progn
           (context-coloring-test-setup)
           (insert (context-coloring-test-read-file ,fixture))
           ,@body)
       (context-coloring-test-cleanup))))

(defun context-coloring-test-with-temp-buffer-async (callback)
  "Create a temporary buffer, and evaluate CALLBACK there.  A
teardown callback is passed to CALLBACK for it to invoke when it
is done."
  (let ((temp-buffer (make-symbol "temp-buffer")))
    (let ((previous-buffer (current-buffer))
          (temp-buffer (generate-new-buffer " *temp*")))
      (set-buffer temp-buffer)
      (funcall
       callback
       (lambda ()
         (and (buffer-name temp-buffer)
              (kill-buffer temp-buffer))
         (set-buffer previous-buffer))))))

(defun context-coloring-test-with-fixture-async (fixture callback &optional setup)
  "Evaluate CALLBACK in a temporary buffer with the relative
FIXTURE.  A teardown callback is passed to CALLBACK for it to
invoke when it is done.  An optional SETUP callback can be passed
to run arbitrary code before the mode is invoked."
  (context-coloring-test-with-temp-buffer-async
   (lambda (done-with-temp-buffer)
     (context-coloring-test-setup)
     (if setup (funcall setup))
     (insert (context-coloring-test-read-file fixture))
     (funcall
      callback
      (lambda ()
        (context-coloring-test-cleanup)
        (funcall done-with-temp-buffer))))))


;;; Test defining utilities

(defun context-coloring-test-js-mode (fixture callback &optional setup)
  "Use FIXTURE as the subject matter for test logic in CALLBACK.
Optionally, provide setup code to run before the mode is
instantiated in SETUP."
  (context-coloring-test-with-fixture-async
   fixture
   (lambda (done-with-test)
     (js-mode)
     (context-coloring-mode)
     (context-coloring-colorize
      (lambda ()
        (funcall callback done-with-test))))
   setup))

(defmacro context-coloring-test-js2-mode (fixture &rest body)
  "Use FIXTURE as the subject matter for test logic in BODY."
  `(context-coloring-test-with-fixture
    ,fixture
    (require 'js2-mode)
    (setq js2-mode-show-parse-errors nil)
    (setq js2-mode-show-strict-warnings nil)
    (js2-mode)
    (context-coloring-mode)
    ,@body))

(defmacro context-coloring-test-deftest-js-mode (name)
  "Define an asynchronous test for `js-mode' in the typical
format."
  (let ((test-name (intern (format "context-coloring-test-js-mode-%s" name)))
        (fixture (format "./fixtures/%s.js" name))
        (function-name (intern-soft (format "context-coloring-test-js-%s" name))))
    `(ert-deftest-async ,test-name (done)
                        (context-coloring-test-js-mode
                         ,fixture
                         (lambda (teardown)
                           (unwind-protect
                               (,function-name)
                             (funcall teardown))
                           (funcall done))))))

(defmacro context-coloring-test-deftest-js2-mode (name)
    "Define a test for `js2-mode' in the typical format."
  (let ((test-name (intern (format "context-coloring-test-js2-mode-%s" name)))
        (fixture (format "./fixtures/%s.js" name))
        (function-name (intern-soft (format "context-coloring-test-js-%s" name))))
    `(ert-deftest ,test-name ()
       (context-coloring-test-js2-mode
        ,fixture
        (,function-name)))))


;;; Assertion functions

(defmacro context-coloring-test-assert-region (&rest body)
  "Skeleton for asserting something about the face of points in a
region.  Provides the free variables `i', `length', `point',
`face' and `actual-level'."
  `(let ((i 0)
         (length (- end start)))
     (while (< i length)
       (let* ((point (+ i start))
              (face (get-text-property point 'face))
              actual-level)
         ,@body)
       (setq i (+ i 1)))))

(defun context-coloring-test-assert-region-level (start end level)
  "Assert that all points in the range [START, END) are of level
LEVEL."
  (context-coloring-test-assert-region
   (when (not (when face
                (let* ((face-string (symbol-name face))
                       (matches (string-match
                                 context-coloring-level-face-regexp
                                 face-string)))
                  (when matches
                    (setq actual-level (string-to-number
                                        (substring face-string
                                                   (match-beginning 1)
                                                   (match-end 1))))
                    (= level actual-level)))))
     (ert-fail (format (concat "Expected level in region [%s, %s), "
                               "which is \"%s\", to be %s; "
                               "but at point %s, it was %s")
                       start end
                       (buffer-substring-no-properties start end) level
                       point actual-level)))))

(defun context-coloring-test-assert-region-face (start end expected-face)
  "Assert that all points in the range [START, END) have the face
EXPECTED-FACE."
  (context-coloring-test-assert-region
   (when (not (eq face expected-face))
     (ert-fail (format (concat "Expected face in region [%s, %s), "
                               "which is \"%s\", to be %s; "
                               "but at point %s, it was %s")
                       start end
                       (buffer-substring-no-properties start end) expected-face
                       point face)))))

(defun context-coloring-test-assert-region-comment-delimiter (start end)
  "Assert that all points in the range [START, END) have
`font-lock-comment-delimiter-face'."
  (context-coloring-test-assert-region-face
   start end 'font-lock-comment-delimiter-face))

(defun context-coloring-test-assert-region-comment (start end)
    "Assert that all points in the range [START, END) have
`font-lock-comment-face'."
  (context-coloring-test-assert-region-face
   start end 'font-lock-comment-face))

(defun context-coloring-test-assert-region-string (start end)
    "Assert that all points in the range [START, END) have
`font-lock-string-face'."
  (context-coloring-test-assert-region-face
   start end 'font-lock-string-face))

(defun context-coloring-test-assert-message (expected)
  "Assert that the *Messages* buffer has message EXPECTED."
  (with-current-buffer "*Messages*"
    (let ((messages (split-string
                     (buffer-substring-no-properties
                      (point-min)
                      (point-max))
                     "\n")))
      (let ((message (car (nthcdr (- (length messages) 2) messages))))
        (should (equal message expected))))))

(defun context-coloring-test-assert-face (level foreground)
  "Assert that a face for LEVEL exists and that its `:foreground'
is FOREGROUND."
  (let* ((face (context-coloring-face-symbol level))
         actual-foreground)
    (when (not face)
      (ert-fail (format (concat "Expected face for level `%s' to exist; "
                                "but it didn't")
                        level)))
    (setq actual-foreground (face-attribute face :foreground))
    (when (not (string-equal foreground actual-foreground))
      (ert-fail (format (concat "Expected face for level `%s' "
                                "to have foreground `%s'; but it was `%s'")
                        level
                        foreground actual-foreground)))))


;;; The tests

(ert-deftest context-coloring-test-unsupported-mode ()
  (context-coloring-test-with-fixture
   "./fixtures/function-scopes.js"
   (context-coloring-mode)
   (context-coloring-test-assert-message
    "Context coloring is not available for this major mode")))

(ert-deftest context-coloring-test-set-colors ()
  ;; This test has an irreversible side-effect in that it defines faces beyond
  ;; 7.  Faces 0 through 7 are reset to their default states, so it might not
  ;; matter, but be aware anyway.
  (context-coloring-set-colors
   "#000000"
   "#111111"
   "#222222"
   "#333333"
   "#444444"
   "#555555"
   "#666666"
   "#777777"
   "#888888"
   "#999999")
  (context-coloring-test-assert-face 0 "#000000")
  (context-coloring-test-assert-face 1 "#111111")
  (context-coloring-test-assert-face 2 "#222222")
  (context-coloring-test-assert-face 3 "#333333")
  (context-coloring-test-assert-face 4 "#444444")
  (context-coloring-test-assert-face 5 "#555555")
  (context-coloring-test-assert-face 6 "#666666")
  (context-coloring-test-assert-face 7 "#777777")
  (context-coloring-test-assert-face 8 "#888888")
  (context-coloring-test-assert-face 9 "#999999"))

(defun context-coloring-test-assert-theme-highest-level (settings expected-level)
  (let (theme)
    (put theme 'theme-settings settings)
    (let ((highest-level (context-coloring-theme-highest-level theme)))
      (when (not (eq highest-level expected-level))
        (ert-fail (format (concat "Expected theme with settings `%s' "
                                  "to have a highest level of `%s', "
                                  "but it was %s.")
                          settings
                          expected-level
                          highest-level))))))

(ert-deftest context-coloring-test-theme-highest-level ()
  (context-coloring-test-assert-theme-highest-level
   '((theme-face foo))
   -1)
  (context-coloring-test-assert-theme-highest-level
   '((theme-face context-coloring-level-0-face))
   0)
  (context-coloring-test-assert-theme-highest-level
   '((theme-face context-coloring-level-1-face))
   1)
  (context-coloring-test-assert-theme-highest-level
   '((theme-face context-coloring-level-1-face)
     (theme-face context-coloring-level-0-face))
   1)
  (context-coloring-test-assert-theme-highest-level
   '((theme-face context-coloring-level-0-face)
     (theme-face context-coloring-level-1-face))
   1)
  )

(defun context-coloring-test-js-function-scopes ()
  (context-coloring-test-assert-region-level 1 9 0)
  (context-coloring-test-assert-region-level 9 23 1)
  (context-coloring-test-assert-region-level 23 25 0)
  (context-coloring-test-assert-region-level 25 34 1)
  (context-coloring-test-assert-region-level 34 35 0)
  (context-coloring-test-assert-region-level 35 52 1)
  (context-coloring-test-assert-region-level 52 66 2)
  (context-coloring-test-assert-region-level 66 72 1)
  (context-coloring-test-assert-region-level 72 81 2)
  (context-coloring-test-assert-region-level 81 82 1)
  (context-coloring-test-assert-region-level 82 87 2)
  (context-coloring-test-assert-region-level 87 89 1))

(context-coloring-test-deftest-js-mode function-scopes)
(context-coloring-test-deftest-js2-mode function-scopes)

(defun context-coloring-test-js-global ()
  (context-coloring-test-assert-region-level 20 28 1)
  (context-coloring-test-assert-region-level 28 35 0)
  (context-coloring-test-assert-region-level 35 41 1))

(context-coloring-test-deftest-js-mode global)
(context-coloring-test-deftest-js2-mode global)

(defun context-coloring-test-js-block-scopes ()
  (context-coloring-test-assert-region-level 20 64 1)
   (setq context-coloring-js-block-scopes t)
   (context-coloring-colorize)
   (context-coloring-test-assert-region-level 20 27 1)
   (context-coloring-test-assert-region-level 27 41 2)
   (context-coloring-test-assert-region-level 41 42 1)
   (context-coloring-test-assert-region-level 42 64 2))

(context-coloring-test-deftest-js2-mode block-scopes)

(defun context-coloring-test-js-catch ()
  (context-coloring-test-assert-region-level 20 27 1)
  (context-coloring-test-assert-region-level 27 51 2)
  (context-coloring-test-assert-region-level 51 52 1)
  (context-coloring-test-assert-region-level 52 73 2)
  (context-coloring-test-assert-region-level 73 101 3)
  (context-coloring-test-assert-region-level 101 102 1)
  (context-coloring-test-assert-region-level 102 117 3)
  (context-coloring-test-assert-region-level 117 123 2))

(context-coloring-test-deftest-js-mode catch)
(context-coloring-test-deftest-js2-mode catch)

(defun context-coloring-test-js-key-names ()
  (context-coloring-test-assert-region-level 20 63 1))

(context-coloring-test-deftest-js-mode key-names)
(context-coloring-test-deftest-js2-mode key-names)

(defun context-coloring-test-js-property-lookup ()
  (context-coloring-test-assert-region-level 20 26 0)
  (context-coloring-test-assert-region-level 26 38 1)
  (context-coloring-test-assert-region-level 38 44 0)
  (context-coloring-test-assert-region-level 44 52 1)
  (context-coloring-test-assert-region-level 57 63 0)
  (context-coloring-test-assert-region-level 63 74 1))

(context-coloring-test-deftest-js-mode property-lookup)
(context-coloring-test-deftest-js2-mode property-lookup)

(defun context-coloring-test-js-key-values ()
  (context-coloring-test-assert-region-level 78 79 1))

(context-coloring-test-deftest-js-mode key-values)
(context-coloring-test-deftest-js2-mode key-values)

(defun context-coloring-test-js-comments-and-strings ()
  (context-coloring-test-assert-region-comment-delimiter 1 4)
  (context-coloring-test-assert-region-comment 4 8)
  (context-coloring-test-assert-region-comment-delimiter 9 12)
  (context-coloring-test-assert-region-comment 12 19)
  (context-coloring-test-assert-region-string 20 32)
  (context-coloring-test-assert-region-level 32 33 0))

(ert-deftest-async context-coloring-test-js-mode-comments-and-strings (done)
  (context-coloring-test-js-mode
   "./fixtures/comments-and-strings.js"
   (lambda (teardown)
     (unwind-protect
         (context-coloring-test-js-comments-and-strings)
       (funcall teardown))
     (funcall done))
   (lambda ()
     (setq context-coloring-comments-and-strings t))))

(ert-deftest context-coloring-test-js2-mode-comments-and-strings ()
  (context-coloring-test-js2-mode
   "./fixtures/comments-and-strings.js"
   (setq context-coloring-comments-and-strings t)
   (context-coloring-colorize)
   (context-coloring-test-js-comments-and-strings)))

(provide 'context-coloring-test)

;;; context-coloring-test.el ends here
