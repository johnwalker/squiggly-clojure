;;; squiggly-clojure.el --- Flycheck: Clojure support    -*- lexical-binding: t; -*-
;;
;; Author: Peter Fraenkel <pnf@podsnap.com>
;; URL: 
;; Version: 1.1.0
;; Package-Requires: ((clojure-mode "2.1.1") (cider "0.8.1") (json "1.4") (flycheck "0.22-cvs1"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of GNU Emacs.


;; Copyright © 2014 Peter Fraenkel
;;
;;; Commentary:
;; Flycheck support for Clojure


;;; Code:

(require 'cider-client)
(require 'flycheck)
(require 'json)



(setq cmdf-ew "(do (require 'eastwood.lint)
    (eastwood.lint/eastwood {:source-paths [\"src\"] :namespaces ['%s] } ))")
(defun parse-ew (out)
  "Parse an output chunk from eastwood: OUT."
  (delq nil
	(mapcar (lambda (s)
	       (let ((r "^\\([^[:space:]]+\\)\\:\\([[:digit:]]+\\)\\:\\([[:digit:]]+\\)\\:[[:space:]]*\\(.*\\)"))
		 (if (string-match r s)
		     (list
		      (match-string 1 s)                     ;; file
		      (string-to-number (match-string 2 s))  ;; line
		      (string-to-number (match-string 3 s))  ;; col
		      (match-string 4 s)                     ;; msg
		      ))))
		(split-string out "\n"))))


(setq cmdf-tc "(do (require 'clojure.core.typed)
                   (require 'clojure.data.json)
                   (clojure.data.json/write-str
                      (map (fn [e] (assoc (:env (ex-data e)) :msg (.getMessage e)))
                      (:delayed-errors (clojure.core.typed/check-ns-info '%s)))))")

(defun get-rec-from-alist (al ks)
  "Extract a list of the values in AL with keys KS."
  (mapcar (lambda (k) (cdr (assoc k al))) ks))

;; Nb. the clojure output gets double-escaped, so we double-decode.
(defun parse-tc-json (s)
  (let ((ws (json-read-from-string (json-read-from-string s))))
    (mapcar (lambda (w) (get-rec-from-alist w '(file line column msg))) ws)))

(defun parse-tc (out)
  "Parse an output chunk from typed clojure: OUT."
  (delq nil
	(mapcar (lambda (s)
	       (let ((r "^\\([^[:space:]]+\\)\\:\\([[:digit:]]+\\)\\:\\([[:digit:]]+\\)\\:[[:space:]]*\\(.*\\)"))
		 (if (string-match r s)
		     (list
		      (match-string 1 s)                     ;; file
		      (string-to-number (match-string 2 s))  ;; line
		      (string-to-number (match-string 3 s))  ;; col
		      (match-string 4 s)                     ;; msg
		      ))))
		(split-string out "__EOE__"))))

(defun tuple-to-error (w checker buffer fname)
  "Convert W of form '(file, line, column, message) to flycheck error object.
Uses CHECKER, BUFFER and FNAME unmodified."
  (pcase-let* ((`(,file ,line ,column ,msg) w))
    (flycheck-error-new-at line column 'error msg
			   :checker checker
			   :buffer buffer
			   :filename fname)))


(defun flycheck-clj-cider-start (checker callback)
  "Invoked by flycheck, which provides CHECKER for identification and a CALLBACK
to which we will pass flycheck error objects."
  (let* ((buffer (current-buffer))
	 (fname  (buffer-file-name buffer))
	 (ns     (cider-current-ns))
	 (cmd-ew (format cmdf-ew ns))
	 (cmd-tc (format cmdf-tc ns))
	 (errors ()))

    ;; cider-eval requests are queued

    (cider-tooling-eval cmd-ew
     (nrepl-make-response-handler
      buffer
      (lambda (_buffer _value)
	  (message "Finished eastwood check."))
      (lambda (_buffer out)
	(mapc (lambda (w) (push (tuple-to-error w checker buffer fname) errors))
	      (parse-ew out)))
      (lambda (_buffer err))
      '()))

    (cider-tooling-eval cmd-tc
     (nrepl-make-response-handler
      buffer
      (lambda (_buffer value)
	(message "Finished core.typed check.")
	(mapc (lambda (w) (push (tuple-to-error w checker buffer fname) errors))  (parse-tc-json value)))
      (lambda (_buffer out)
	;(message out)
	)
      (lambda (_buffer err))
      '())
     )

    (cider-tooling-eval "true"
		(nrepl-make-response-handler
		 buffer
		 (lambda (_buffer _value)
		   (message "Finished all clj checks.")
		   ;;(print errors)
		   (funcall callback 'finished errors))
		 (lambda (_buffer out))
		 (lambda (_buffer err))
		 '()))
    ))

(flycheck-define-generic-checker 'clojure-cider-checker
  "A syntax checker for Clojure using Cider"
  :start #'flycheck-clj-cider-start
  :modes '(clojure-mode)
  )

(add-to-list 'flycheck-checkers 'clojure-cider-checker)

(provide 'squiggly-clojure)
;;; squiggly-clojure.el ends here

