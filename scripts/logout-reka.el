;;; -*- lexical-binding: t -*-
;;; Native application inventory for the shared graphical logout dialog.

(require 'json)

(defun jd-reka-logout-inventory ()
  "Return real application windows as JSON, excluding the WM's own frames."
  (json-serialize
   (vconcat
    (mapcar
     (lambda (buffer)
       (with-current-buffer buffer
         (unless reka-identifier
           (error "Application window metadata is still arriving"))
         (list :identifier reka-identifier
               :app_id (or reka-app-id :null)
               :title (or reka-title (buffer-name)))))
     (append (reka--list-buffers) nil)))))

(defun jd-reka-logout-close (identifier)
  "Send one native close request for the application with IDENTIFIER."
  (when-let* ((buffer (seq-find
                      (lambda (candidate)
                        (equal identifier
                               (buffer-local-value 'reka-identifier candidate)))
                      (append (reka--list-buffers) nil))))
    (reka-request-close buffer)
    t))
