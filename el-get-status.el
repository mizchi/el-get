;;; el-get --- Manage the external elisp bits and pieces you depend upon
;;
;; Copyright (C) 2010-2011 Dimitri Fontaine
;;
;; Author: Dimitri Fontaine <dim@tapoueh.org>
;; URL: http://www.emacswiki.org/emacs/el-get
;; GIT: https://github.com/dimitri/el-get
;; Licence: WTFPL, grab your copy here: http://sam.zoy.org/wtfpl/
;;
;; This file is NOT part of GNU Emacs.
;;
;; Install
;;     Please see the README.asciidoc file from the same distribution

;;
;; package status --- a plist saved on a file, using symbols
;;
;; it should be possible to use strings instead, but in my tests it failed
;; miserably.
;;

(require 'cl)
(require 'pp)
(require 'el-get-core)

(defun el-get-package-name (package-symbol)
  "Returns a package name as a string."
  (cond ((keywordp package-symbol)
         (substring (symbol-name package-symbol) 1))
        ((symbolp package-symbol)
         (symbol-name package-symbol))
        ((stringp package-symbol)
         package-symbol)
        (t (error "Unknown package: %s"))))

(defun el-get-package-symbol (package)
  "Returns a package name as a non-keyword symbol"
  (cond ((keywordp package)
         (intern (substring (symbol-name package) 1)))
        ((symbolp package)
         package)
        ((stringp package) (intern package))
        (t (error "Unknown package: %s"))))

(defun el-get-package-keyword (package-name)
  "Returns a package name as a keyword :package."
  (if (keywordp package-name)
      package-name
    (intern (format ":%s" package-name))))

(defun el-get-pp-status-alist-to-string (object)
  (with-temp-buffer
    (lisp-mode-variables nil)
    (set-syntax-table emacs-lisp-mode-syntax-table)
    (let ((print-escape-newlines pp-escape-newlines)
          (print-quoted t))
      (prin1 object (current-buffer)))
    (goto-char (point-min))
    ;; Each (apparently-infinite) loop constantly moves forward
    ;; through the element it is processing (via `down-list`,
    ;; `up-list`, and `forward-sexp` and finally throws a scan-error
    ;; when it reaches the end of the element, which breaks out of the
    ;; loop and is caught by `condition-case`.
    (condition-case err
        (progn
          ;; Descend into status list"
          (down-list 1)
          (while t
            ;; Descend into status entry for next package
            (down-list 1)
            (condition-case err
                (progn
                  ;; Get to the beginning of the recipe
                  (down-list 1)
                  (up-list -1)
                  ;; Kill the recipe
                  (kill-sexp)
                  ;; Reprint the recipe with newlines between
                  ;; key-value pairs
                  (insert "(")
                  (let ((recipe (car (read-from-string (car kill-ring)))))
                    (loop for (prop val) on recipe by 'cddr
                          do (insert
                              (format "%s %s\n"
                                      (prin1-to-string prop)
                                      (prin1-to-string val)))))
                  (insert ")"))
              (scan-error nil))
            ;; Exit from status entry for this package
            (up-list 1)))
      (scan-error nil))
    (pp-buffer)
    (goto-char (point-min))
    ;; Make sure we didn't change the value. That would be bad.
    (if (equal object (read (current-buffer)))
        (buffer-string)
      ;; If the pretty-printing function *did* change the value, just
      ;; use the built-in pretty-printing instead. It's not as good,
      ;; but at least it's correct.
      (warn "The custom pretty-printer for the .status.el failed. The original value and pretty-printed-value are shown below. You can try to see where they differ and report a bug.\n---BEGIN ORIGINAL VALUE---\n%s\n---END ORIGINAL VALUE---\n\n---BEGIN PRETTY-PRINTED VALUE---\n%s\n---END PRETTY-PRINTED VALUE---\n"
            (pp-to-string object)
            (buffer-string))
      (pp-to-string object))))

(defun el-get-save-package-status (package status)
  "Save given package status"
  (let* ((package (el-get-as-symbol package))
         (recipe (when (string= status "installed")
                   (el-get-package-def package)))
         (package-status-alist
          (assq-delete-all package (el-get-read-status-file)))
         (new-package-status-alist
          (sort (append package-status-alist
                        (list            ; alist of (PACKAGE . PROPERTIES-LIST)
                         (cons package (list 'status status 'recipe recipe))))
                (lambda (p1 p2)
                  (string< (el-get-as-string (car p1))
                           (el-get-as-string (car p2)))))))
    (with-temp-file el-get-status-file
      (insert (el-get-pp-status-alist-to-string new-package-status-alist)))
    ;; Return the new alist
    new-package-status-alist))

(defun el-get-read-status-file ()
  "read `el-get-status-file' and return an alist of plist like:
   (PACKAGE . (status \"status\" recipe (:name ...)))"
  (let ((ps
         (when (file-exists-p el-get-status-file)
           (car (with-temp-buffer
                  (insert-file-contents-literally el-get-status-file)
                  (read-from-string (buffer-string)))))))
    (if (consp (car ps))         ; check for an alist, new format
        ps
      ;; convert to the new format, fetching recipes as we go
      (loop for (p s) on ps by 'cddr
            for psym = (el-get-package-symbol p)
            when psym
            collect (cons psym
                          (list 'status s
                                'recipe (when (string= s "installed")
                                          (el-get-package-def psym))))))))

(defun el-get-package-status-alist (&optional package-status-alist)
  "return an alist of (PACKAGE . STATUS)"
  (loop for (p . prop) in (or package-status-alist
                              (el-get-read-status-file))
        collect (cons p (plist-get prop 'status))))

(defun el-get-package-status-recipes (&optional package-status-alist)
  "return the list of recipes stored in the status file"
  (loop for (p . prop) in (or package-status-alist
                              (el-get-read-status-file))
        when (string= (plist-get prop 'status) "installed")
        collect (plist-get prop 'recipe)))

(defun el-get-read-package-status (package &optional package-status-alist)
  "return current status for PACKAGE"
  (let ((p-alist (or package-status-alist (el-get-read-status-file))))
    (plist-get (cdr (assq (el-get-as-symbol package) p-alist)) 'status)))

(define-obsolete-function-alias 'el-get-package-status 'el-get-read-package-status)

(defun el-get-read-package-status-recipe (package &optional package-status-alist)
  "return current status recipe for PACKAGE"
  (let ((p-alist (or package-status-alist (el-get-read-status-file))))
    (plist-get (cdr (assq (el-get-as-symbol package) p-alist)) 'recipe)))

(defun el-get-filter-package-alist-with-status (package-status-alist &rest statuses)
  "Return package names that are currently in given status"
  (loop for (p . prop) in package-status-alist
        for s = (plist-get prop 'status)
	when (member s statuses)
        collect (el-get-as-string p)))

(defun el-get-list-package-names-with-status (&rest statuses)
  "Return package names that are currently in given status"
  (apply #'el-get-filter-package-alist-with-status
         (el-get-read-status-file)
         statuses))

(defun el-get-read-package-with-status (action &rest statuses)
  "Read a package name in given status"
  (completing-read (format "%s package: " action)
                   (apply 'el-get-list-package-names-with-status statuses)))

(defun el-get-count-package-with-status (&rest statuses)
  "Return how many packages are currently in given status"
  (length (apply #'el-get-list-package-names-with-status statuses)))

(defun el-get-count-packages-with-status (packages &rest statuses)
  "Return how many packages are currently in given status in PACKAGES"
  (length (intersection
           (mapcar #'el-get-as-symbol (apply #'el-get-list-package-names-with-status statuses))
           (mapcar #'el-get-as-symbol packages))))

(defun el-get-extra-packages (&rest packages)
  "Return installed or required packages that are not in given package list"
  (let ((packages
	 ;; &rest could contain both symbols and lists
	 (loop for p in packages
	       when (listp p) append (mapcar 'el-get-as-symbol p)
	       else collect (el-get-as-symbol p))))
    (when packages
      (loop for (p . prop) in (el-get-read-status-file)
            for s = (plist-get prop 'status)
            for x = (el-get-package-symbol p)
            unless (member x packages)
            unless (equal s "removed")
            collect (list x s)))))

(defmacro el-get-with-status-sources (&rest body)
  "Evaluate BODY with `el-get-sources' bound to recipes from status file."
  `(let ((el-get-sources (el-get-package-status-recipes)))
     (progn ,@body)))
(put 'el-get-with-status-recipes 'lisp-indent-function
     (get 'progn 'lisp-indent-function))

(provide 'el-get-status)
