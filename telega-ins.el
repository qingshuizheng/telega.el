;;; telega-ins.el --- Inserters for the telega  -*- lexical-binding:t -*-

;; Copyright (C) 2018 by Zajcev Evgeny.

;; Author: Zajcev Evgeny <zevlg@yandex.ru>
;; Created: Sat Jul 14 19:06:40 2018
;; Keywords:

;; telega is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; telega is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with telega.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Inserter is the function that inserts some content.
;; Different inserters accepts different arguments
;; Inserter can examine previously inserted content.
;; Inserter returns non-nil if something was inserted and nil if
;; nothing has been inserted.

;;; Code:
(require 'telega-core)
(require 'telega-inline)                ;telega-inline--callback
(require 'telega-customize)

(defun telega-ins (&rest args)
  "Insert all strings in ARGS.
Return non-nil if something has been inserted."
  (< (prog1 (point) (apply 'insert args)) (point)))

(defmacro telega-ins-fmt (fmt &rest args)
  "Insert string formatted by FMT and ARGS.
Return `t'."
  (declare (indent 1))
  `(telega-ins (format ,fmt ,@args)))

(defmacro telega-ins--as-string (&rest body)
  "Execute BODY inserters and return result as a string."
  `(with-temp-buffer
     ,@body
     (buffer-string)))

(defmacro telega-ins--one-lined (&rest body)
  "Execute BODY making insertation one-lined.
It makes one line by replacing all newlines by spaces."
  `(telega-ins
    (replace-regexp-in-string
     "\n" " " (telega-ins--as-string ,@body))))

(defmacro telega-ins--with-attrs (attrs &rest body)
  "Execute inserters applying ATTRS after insertation.
Return `t'."
  (declare (indent 1))
  `(telega-ins
    (telega-fmt-eval-attrs (telega-ins--as-string ,@body) ,attrs)))

(defmacro telega-ins--with-face (face &rest body)
  "Execute BODY highlighting result with FACE."
  (declare (indent 1))
  `(telega-ins--with-attrs (list :face ,face)
     ,@body))

(defmacro telega-ins--column (column fill-col &rest body)
  "Execute BODY at COLUMN filling to FILL-COLL.
If COLUMN is nil or less then current column, then current column is used."
  (declare (indent 2))
  (let ((colsym (gensym "col"))
        (curcol (gensym "curcol")))
    `(let ((,colsym ,column)
           (,curcol (telega-current-column)))
       (when (or (null ,colsym) (< ,colsym ,curcol))
         (setq ,colsym ,curcol))

       (telega-ins (make-string (- ,colsym ,curcol) ?\s))
;       (move-to-column ,colsym t)
       (telega-ins--with-attrs
           (list :fill 'left
                 :fill-prefix (make-string ,colsym ?\s)
                 :fill-column ,fill-col)
         ,@body))))

(defmacro telega-ins--labeled (label fill-col &rest body)
  "Execute BODY filling it to FILL-COLL, prefixing first line with LABEL."
  (declare (indent 2))
  `(progn
     (telega-ins ,label)
     (telega-ins--column nil ,fill-col
       ,@body)))

(defun telega-ins--button (label &rest props)
  "Insert pressable button labeled with LABEL.
If custom face is specified in PROPS, then
`telega-button--sensor-func' is not set as sensor function."
  (declare (indent 1))
  (unless (plist-get props 'face)
    ;; XXX inclose LABEL with shrink version of spaces, so button
    ;; width will be char aligned

    ;; NOTE: non-breakable space is used, so if line is feeded at the
    ;; beginning of button, it won't loose its leading space
    (let* ((box-width (- (or (plist-get (face-attribute 'telega-button :box)
                                        :line-width)
                             0)))
           (space `(space (,(- (frame-char-width) box-width)))))
      (setq label (concat (propertize "\u00A0" 'display space)
                          label
                          (propertize "\u00A0" 'display space))))
    (setq props (plist-put props 'face 'telega-button))
    (setq props (plist-put props 'cursor-sensor-functions
                           '(telega-button--sensor-func))))
  (unless (plist-get props 'action)
    (setq props (plist-put props 'action
                           (lambda (button)
                             (funcall (button-get button :action)
                                      (button-get button :value))))))
  (button-at (apply 'insert-text-button label props)))

(defmacro telega-ins--raw-button (props &rest body)
  "Execute BODY creating text button with PROPS."
  (declare (indent 1))
  `(button-at (apply 'make-text-button (prog1 (point) ,@body) (point)
                     ,props)))

(defmacro telega-ins--with-props (props &rest body)
  "Execute inserters applying PROPS after insertation.
Return what BODY returns."
  (declare (indent 1))
  (let ((spnt-sym (gensym "pnt")))
    `(let ((,spnt-sym (point)))
       (prog1
           (progn ,@body)
         (add-text-properties ,spnt-sym (point) ,props)))))

(defmacro telega-ins-prefix (prefix &rest body)
  "In case BODY inserted anything then PREFIX is also inserted before BODY."
  (declare (indent 1))
  (let ((spnt-sym (gensym "pnt")))
    `(let ((,spnt-sym (point)))
       (when (progn ,@body)
         (save-excursion
           (goto-char ,spnt-sym)
           (telega-ins ,prefix))))))

(defun telega-ins--image (img &optional slice-num props)
  "Insert image IMG generated by telega.
Uses internal `:telega-text' to keep correct column.
If SLICE-NUM is specified, then insert N's."
  (let* ((img-size (image-size img))
         (slice (when slice-num
                  (let ((slice-h (frame-char-height))
                        (nslices (ceiling (cdr img-size))))
                    (when (>= slice-num nslices)
                      (error "Can't insert %d slice, image has only %d slices"
                             slice-num nslices))
                    (list 0 (* slice-num slice-h) 1.0 slice-h)))))
    (telega-ins--with-props
        (nconc (list 'rear-nonsticky '(display))
               (list 'display
                     (if slice
                         (list (cons 'slice slice) img)
                       img))
               props)
      (telega-ins
       (or (plist-get (cdr img) :telega-text)
           (make-string (ceiling (car img-size)) ?X))))))

(defun telega-ins--image-slices (image &optional props)
  "Insert sliced IMAGE at current column.
PROPS - additional image properties."
  (let ((img-slices (ceiling (cdr (image-size image)))))
    (telega-ins--column (current-column) nil
      (dotimes (slice-num img-slices)
        (telega-ins--image image slice-num props)
        (unless (= slice-num (1- img-slices))
          (telega-ins--with-props (list 'line-height t)
            (telega-ins "\n")))))))


;; Various inserters
(defun telega-ins--actions (actions)
  "Insert chat ACTIONS alist."
  (when actions
    ;; NOTE: Display only last action
    (let* ((user (telega-user--get (caar actions)))
           (action (cdar actions)))
      (telega-ins (telega-user--name user 'short) " ")
      (telega-ins
       (propertize (concat "is " (substring (plist-get action :@type) 10))
                   'face 'shadow)))))

(defun telega-ins--filesize (filesize)
  "Insert FILESIZE in human readable format."
  (telega-ins (file-size-human-readable filesize)))

(defun telega-ins--date (timestamp)
  "Insert DATE.
Format is:
- HH:MM      if today
- Mon/Tue/.. if on this week
- DD.MM.YY   otherwise"
  (let* ((dtime (decode-time timestamp))
         (current-ts (time-to-seconds (current-time)))
         (ctime (decode-time current-ts))
         (today00 (telega--time-at00 current-ts ctime)))
    (if (> timestamp today00)
        (telega-ins-fmt "%02d:%02d" (nth 2 dtime) (nth 1 dtime))

      (let* ((week-day (nth 6 ctime))
             (mdays (+ week-day
                       (- (if (< week-day telega-week-start-day) 7 0)
                          telega-week-start-day)))
             (week-start00 (telega--time-at00
                            (- current-ts (* mdays 24 3600)))))
        (if (> timestamp week-start00)
            (telega-ins (nth (nth 6 dtime) telega-week-day-names))

          (telega-ins-fmt "%02d.%02d.%02d"
            (nth 3 dtime) (nth 4 dtime) (- (nth 5 dtime) 2000))))
      )))

(defun telega-ins--date-iso8601 (timestamp &rest args)
  "Insert TIMESTAMP in ISO8601 format."
  (apply 'telega-ins (format-time-string "%FT%T%z" timestamp) args))

(defun telega-ins--date-full (timestamp &rest args)
  "Insert TIMESTAMP in full format - DAY MONTH YEAR."
  (apply 'telega-ins (format-time-string "%d %B %Y" timestamp) args))

(defun telega-ins--username (user-id &optional fmt-type)
  "Insert username for user denoted by USER-ID
FMT-TYPE is passed directly to `telega-user--name' (default=`short')."
  (unless (zerop user-id)
    (telega-ins
     (telega-user--name (telega-user--get user-id) (or fmt-type 'short)))))

(defun telega-ins--chat-member-status (status)
  "Format chat member STATUS."
  (unless (eq (telega--tl-type status) 'chatMemberStatusMember)
    (telega-ins (downcase (substring (plist-get status :@type) 16)))))

(defun telega-ins--user-status (user)
  "Insert USER's online status."
  ;; TODO: check online's `:expires'
  (let* ((status (telega--tl-type (plist-get user :status)))
         (online-dur (- (telega-time-seconds)
                        (or (plist-get user :telega-last-online) 0))))
    (telega-ins--with-face (if (eq status 'userStatusOnline)
                               'telega-user-online-status
                             'telega-user-non-online-status)
      (telega-ins
       (cond ((eq status 'userStatusOnline)
              ;; I18N: lng_status_online
              "online")
             ((< online-dur 60)
              ;; I18N: lng_status_lastseen_now
              "last seen just now")
             ((< online-dur (* 3 24 60 60))
              (format "last seen in %s"
                      (telega-duration-human-readable online-dur 1)))
             ((eq status 'userStatusRecently)
              ;; I18N: lng_status_recently
              "last seen recently")
             (t
              ;; TODO: other cases
              (symbol-name status)))))))

(defun telega-ins--user (user &optional member)
  "Insert USER, aligning multiple lines at current column."
  (let* ((joined (plist-get member :joined_chat_date))
         (avatar (telega-user-avatar-image user))
         (off-column (telega-current-column)))
    (telega-ins--image avatar 0)
    (telega-ins (telega-user--name user))
    (when (and member
               (telega-ins-prefix " ("
                 (telega-ins--chat-member-status
                  (plist-get member :status))))
      (telega-ins ")"))
    (telega-ins "\n")
    (telega-ins (make-string off-column ?\s))
    (telega-ins--image avatar 1)
    (telega-ins--user-status user)
    ;; TODO: for member insert join date
    ;;  (unless (zerop joined)
    ;;    (concat " joined at " (telega-fmt-timestamp joined))))))
    ))

(defun telega-ins--chat-member (member)
  "Formatting for the chat MEMBER.
Return COLUMN at which user name is inserted."
  (telega-ins--user
   (telega-user--get (plist-get member :user_id)) member))

(defun telega-ins--chat-members (members)
  "Insert chat MEMBERS list."
  (let ((last-member (unless (zerop (length members))
                       (aref members (1- (length members)))))
        (delim-col 5))
    (seq-doseq (member members)
      (telega-ins " ")
      (telega-button--insert 'telega-member member)

      ;; Insert the delimiter
      (unless (eq member last-member)
        (telega-ins "\n")
        ;; NOTE: to apply `height' property \n must be included
        (telega-ins--with-props
            '(face default display ((space-width 2) (height 0.5)))
          (telega-ins--column delim-col nil
            (telega-ins (make-string 30 ?─) "\n")))))
    (telega-ins "\n")))

(defun telega-ins--via-bot (via-bot-user-id)
  "Insert via bot user."
  (unless (zerop via-bot-user-id)
    (telega-ins
     "via "
     (apply 'propertize
            (telega-user--name (telega-user--get via-bot-user-id) 'short)
            (telega-link-props 'user via-bot-user-id)))))

(defun telega-ins--file-progress (msg file)
  "Insert Upload/Download status for the document."
  (let ((file-id (plist-get file :id))
        (local (plist-get file :local)))
    ;; Downloading status:
    ;;   /link/to-file         if file has been downloaded
    ;;   [Download]            if no local copy
    ;;   [...   20%] [Cancel]  if download in progress
    (cond ((telega-file--uploading-p file)
           (let ((progress (telega-file--uploading-progress file)))
             (telega-ins-fmt "[%-10s%d%%] "
               (make-string (round (* progress 10)) ?\.)
               (round (* progress 100)))
             (telega-ins--button "Cancel"
               'action (lambda (_ignored)
                         (telega--cancelUploadFile file-id)))))

          ((telega-file--downloading-p file)
           (let ((progress (telega-file--downloading-progress file)))
             (telega-ins-fmt "[%-10s%d%%] "
               (make-string (round (* progress 10)) ?\.)
               (round (* progress 100)))
             (telega-ins--button "Cancel"
               'action (lambda (_ignored)
                         (telega--cancelDownloadFile file-id)))))

          ((not (telega-file--downloaded-p file))
           (telega-ins--button "Download"
             'action (lambda (_ignored)
                       (telega-file--download file 32
                         (lambda (_fileignored)
                           (telega-msg-redisplay msg)))))))
    ))

(defun telega-ins--outgoing-status (msg)
  "Insert outgoing status of the message MSG."
  (when (plist-get msg :is_outgoing)
    (let ((sending-state (plist-get (plist-get msg :sending_state) :@type))
          (chat (telega-chat-get (plist-get msg :chat_id))))
      (telega-ins--with-face 'telega-msg-outgoing-status
        (telega-ins
         (cond ((and (stringp sending-state)
                     (string= sending-state "messageSendingStatePending"))
                telega-symbol-pending)
               ((and (stringp sending-state)
                     (string= sending-state "messageSendingStateFailed"))
                telega-symbol-failed)
               ((>= (plist-get chat :last_read_outbox_message_id)
                    (plist-get msg :id))
                telega-symbol-heavy-checkmark)
               (t telega-symbol-checkmark)))))))

(defun telega-ins--text (text &optional as-markdown)
  "Insert TEXT applying telegram entities.
If AS-MARKDOWN is non-nil, then instead of applying faces, apply
markdown syntax to the TEXT."
  (when text
    (telega-ins
     (funcall (if as-markdown
                  'telega--entities-as-markdown
                'telega--entities-as-faces)
              (plist-get text :entities) (plist-get text :text)))))

(defun telega-ins--photo (photo &optional msg limits)
  "Inserter for the PHOTO."
  (let* ((hr (telega-photo--highres photo))
         (hr-file (telega-file--renew hr :photo)))
    ;; Show downloading status of highres thumbnail
    (when (and (telega-file--downloading-p hr-file) msg)
      ;; Monitor downloading progress for the HR-FILE
      (telega-file--download hr-file 32
        (lambda (_fileignored)
          (telega-msg-redisplay msg)))

      (telega-ins telega-symbol-photo " " (plist-get photo :id))
      (telega-ins-fmt " (%dx%d) " (plist-get hr :width) (plist-get hr :height))
      (telega-ins--file-progress msg hr-file)
      (telega-ins "\n"))

    (telega-ins--image-slices
     (telega-photo--image photo (or limits telega-photo-maxsize)))
    ))

(defun telega-ins--audio (msg &optional audio)
  "Insert audio message MSG."
  (unless audio
    (setq audio (telega--tl-get msg :content :audio)))
  (let* ((dur (plist-get audio :duration))
        (proc (plist-get msg :telega-audio-proc))
        (proc-status (and (process-live-p proc)
                          (process-status proc)))
        (played (and proc-status
                     (plist-get (process-plist proc) :progress)))

        (thumb (plist-get audio :album_cover_thumbnail))
        (audio-name (plist-get audio :file_name))
        (audio-file (telega-file--renew audio :audio))
        (title (plist-get audio :title))
        (performer (plist-get audio :performer))
        linup-col)

    ;; play/pause
    (if (eq proc-status 'run)
        (telega-ins telega-symbol-pause)
      (telega-ins telega-symbol-play))
    (telega-ins " ")

    (telega-ins--with-attrs (list :max (/ telega-chat-fill-column 2)
                                  :elide t
                                  :elide-trail (/ telega-chat-fill-column 4))
      (if (telega-file--downloaded-p audio-file)
          (let ((local-path (telega--tl-get audio-file :local :path)))
            (telega-ins--with-props
                (telega-link-props 'file local-path)
              (telega-ins (telega-short-filename local-path))))
        (telega-ins audio-name)))
    (telega-ins-fmt " (%s %s)"
      (file-size-human-readable (telega-file--size audio-file))
      (telega-duration-human-readable dur))
    (telega-ins-prefix " "
      (telega-ins--file-progress msg audio-file))

    ;; Title --Performer
    (when title
      (telega-ins "\n")
      (telega-ins--with-face 'bold
        (telega-ins title))
      (telega-ins-prefix " --"
        (telega-ins performer)))

    ;; Progress and [Stop] button
    (when played
      (telega-ins "\n")
      (let* ((pcol (/ telega-chat-fill-column 2))
             (progress (/ played dur))
             (ps (make-string (round (* progress pcol)) ?\.))
             (pl (make-string (- pcol (string-width ps)) ?\s)))
        (telega-ins "[" ps pl "] ")
        (telega-ins--button "Stop"
          'action (lambda (_ignored)
                    (telega-ffplay-stop)))))

    ;; Album cover
    (when thumb
      (telega-ins "\n")
      (let ((timg (telega-media--image
                   (cons thumb 'telega-thumb--create-image-as-is)
                   (cons thumb :photo))))
        (telega-ins--image-slices timg))
      (telega-ins " "))
    t))

(defun telega-ins--video (msg &optional video)
  "Insert video message MSG."
  (unless video
    (setq video (telega--tl-get msg :content :video)))
  (let ((thumb (plist-get video :thumbnail))
        (video-name (plist-get video :file_name))
        (video-file (telega-file--renew video :video)))
    (telega-ins telega-symbol-video " ")
    (if (telega-file--downloaded-p video-file)
        (let ((local-path (telega--tl-get video-file :local :path)))
          (telega-ins--with-props
              (telega-link-props 'file local-path)
            (telega-ins (telega-short-filename local-path))))
      (telega-ins video-name))
    (telega-ins-fmt " (%dx%d %s %s)"
      (plist-get video :width)
      (plist-get video :height)
      (file-size-human-readable (telega-file--size video-file))
      (telega-duration-human-readable (plist-get video :duration)))
    (telega-ins-prefix " "
      (telega-ins--file-progress msg video-file))

    (when thumb
      (telega-ins "\n")
      (let ((timg (telega-media--image
                   (cons thumb 'telega-thumb--create-image-as-is)
                   (cons thumb :photo))))
        (telega-ins--image-slices timg))
      (telega-ins " "))
    t))

(defun telega-ins--voice-note (msg &optional note)
  "Insert message with voiceNote content."
  (unless note
    (setq note (telega--tl-get msg :content :voice_note)))
  (let* ((dur (plist-get note :duration))
         (proc (plist-get msg :telega-vvnote-proc))
         (proc-status (and (process-live-p proc)
                           (process-status proc)))
         (played (and proc-status
                      (plist-get (process-plist proc) :progress)))
         (note-file (telega-file--renew note :voice))
         (waveform (plist-get note :waveform))
         (waves (telega-vvnote--waveform-decode waveform))
         (listened-p (telega--tl-get msg :content :is_listened)))

    ;; play/pause
    (if (eq proc-status 'run)
        (telega-ins telega-symbol-pause)
      (telega-ins telega-symbol-play))
    (telega-ins " ")

    ;; waveform image
    (telega-ins--image
     (telega-vvnote--waves-svg
      waves (* telega-vvnote-waves-height-factor
               (frame-char-height (telega-x-frame)))
      dur played))

    ;; duration and download status
    (telega-ins " (" (telega-duration-human-readable dur) ")")
    (when listened-p
      (telega-ins telega-symbol-eye))
    (telega-ins-prefix " "
      (telega-ins--file-progress msg note-file))
    ))

(defun telega-ins--video-note (msg &optional note)
  "Insert message with videoNote content."
  (unless note
    (setq note (telega--tl-get msg :content :video_note)))
  (let* ((dur (plist-get note :duration))
         (thumb (plist-get note :thumbnail))
         (note-file (telega-file--renew note :video))
         (viewed-p (telega--tl-get msg :content :is_viewed)))

    (telega-ins (propertize "NOTE" 'face 'shadow))
    (telega-ins-fmt " (%dx%d %s %s)"
      (plist-get note :length) (plist-get note :length)
      (file-size-human-readable (telega-file--size note-file))
      (telega-duration-human-readable (plist-get note :duration)))
    (when viewed-p
      (telega-ins telega-symbol-eye))
    (telega-ins-prefix " "
      (telega-ins--file-progress msg note-file))

    (telega-ins "\n")
    (when thumb
      (let ((timg (telega-media--image
                   (cons thumb 'telega-thumb--create-image-as-is)
                   (cons thumb :photo))))
        (telega-ins--image-slices timg))
      (telega-ins " "))
    ))

(defun telega-ins--document (msg &optional doc)
  "Insert document DOC."
  (unless doc
    (setq doc (telega--tl-get msg :content :document)))
  (let* ((fname (plist-get doc :file_name))
         (thumb (plist-get doc :thumbnail))
         (doc-file (telega-file--renew doc :document)))
    (telega-ins telega-symbol-attachment " ")

    (if (telega-file--downloaded-p doc-file)
        (let ((local-path (telega--tl-get doc-file :local :path)))
          (telega-ins--with-props (telega-link-props 'file local-path)
            (telega-ins (telega-short-filename local-path))))
      (telega-ins fname))
    (telega-ins " (" (file-size-human-readable
                      (telega-file--size doc-file)) ") ")
    (telega-ins--file-progress msg doc-file)

    ;; documents thumbnail preview (if any)
    (when thumb
      (telega-ins "\n")
      (let ((timg (telega-media--image
                   (cons thumb 'telega-thumb--create-image-as-is)
                   (cons thumb :photo))))
        (telega-ins--image-slices timg))
      (telega-ins " "))
    ))

(defun telega-ins--webpage (msg &optional web-page)
  "Insert WEB-PAGE.
Return `non-nil' if WEB-PAGE has been inserted."
  (unless web-page
    (setq web-page (telega--tl-get msg :content :web_page)))
  (let ((sitename (plist-get web-page :site_name))
        (title (plist-get web-page :title))
        (desc (plist-get web-page :description))
        (instant-view-p (plist-get web-page :has_instant_view))
        (photo (plist-get web-page :photo))
        (width (- telega-chat-fill-column 10)))
    (when web-page
      (telega-ins telega-symbol-vertical-bar)
      (telega-ins--with-attrs (list :fill-prefix telega-symbol-vertical-bar
                                    :fill-column width
                                    :fill 'left)
        (when (telega-ins--with-face 'telega-webpage-sitename
                (telega-ins sitename))
          (telega-ins "\n"))
        (when (telega-ins--with-face 'telega-webpage-title
                (telega-ins title))
          (telega-ins "\n"))
        (when (telega-ins desc)
          (telega-ins "\n"))

        (when photo
          (telega-ins--photo photo msg)
          (telega-ins "\n"))
       (cl-case (intern (plist-get web-page :type))
         (document
          (let ((doc (plist-get web-page :document)))
            (when doc
              (telega-ins--document msg doc))))
         (video
          (let ((video (plist-get web-page :video)))
            (when video
              (telega-ins "<TODO: webPage:video>"))))))

       (when instant-view-p
         (telega-ins--button
             (concat "  " telega-symbol-thunder " INSTANT VIEW  ")
           'action 'telega-msg-button--iv-action)
         (telega-ins "\n"))

       ;; Remove trailing newline, if any
       (when (= (char-before) ?\n)
         (delete-char -1))
       t)))

(defun telega-ins--location (location)
  "Inserter for the LOCATION."
  (telega-ins telega-symbol-location " ")
  (telega-ins-fmt "%fN, %fE"
    (plist-get location :latitude) (plist-get location :longitude)))

(defun telega-ins--contact (contact)
  "One line variant inserter for CONTACT."
  (telega-ins telega-symbol-contact " ")
  (when (telega-ins (plist-get contact :first_name))
    (telega-ins " "))
  (when (telega-ins (plist-get contact :last_name))
    (telega-ins " "))
  (telega-ins "(" (plist-get contact :phone_number) ")"))

(defun telega-ins--contact-msg (msg)
  "Inserter for contact message MSG."
  ;; Two lines for the contact
  (let* ((content (plist-get msg :content))
         (contact (plist-get content :contact))
         (user-id (plist-get contact :user_id))
         (user (unless (zerop user-id) (telega-user--get user-id)))
         (user-ava (when user
                     (telega-user-avatar-image user))))
    (when user-ava
      (telega-ins--image user-ava 0))
    (telega-ins--contact (plist-get content :contact))
    (telega-ins "\n")
    (when user-ava
      (telega-ins--image user-ava 1))
    (telega-ins--button (concat "   VIEW CONTACT   ")
      'action 'telega-msg-button--action)))

(defun telega-ins--invoice (invoice)
  "Insert invoice message MSG."
  (let ((title (plist-get invoice :title))
        (desc (plist-get invoice :description))
        (photo (plist-get invoice :photo)))
    (telega-ins telega-symbol-invoice " ")
    (telega-ins-fmt "%.2f%s" (/ (plist-get invoice :total_amount) 100.0)
                    (plist-get invoice :currency))
    (when (plist-get invoice :is_test)
      (telega-ins " (Test)"))
    (telega-ins "\n")
    (when photo
      (telega-ins--photo photo)
      (telega-ins "\n"))
    (telega-ins--with-face 'telega-webpage-title
      (telega-ins title))
    (telega-ins "\n")
    (telega-ins desc)))

(defun telega-ins--animation-msg (msg &optional animation)
  "Inserter for animation message MSG."
  (unless animation
    (setq animation (telega--tl-get msg :content :animation)))
  (let ((anim-file (telega-file--renew animation :animation))
        (thumb (plist-get animation :thumbnail)))
    (telega-ins (propertize "GIF" 'face 'shadow) " ")
    (if (telega-file--downloaded-p anim-file)
        (let ((local-path (telega--tl-get anim-file :local :path)))
          (telega-ins--with-props
              (telega-link-props 'file local-path)
            (telega-ins (telega-short-filename local-path))))
      (telega-ins (plist-get animation :file_name)))
    (telega-ins-fmt " (%dx%d %s %s)"
      (plist-get animation :width)
      (plist-get animation :height)
      (file-size-human-readable (telega-file--size anim-file))
      (telega-duration-human-readable (telega--tl-get animation :duration)))
    (telega-ins-prefix " "
      (telega-ins--file-progress msg anim-file))
    (telega-ins "\n")

    (telega-ins--image-slices
     (telega-media--image
      (cons thumb 'telega-thumb--create-image-as-is)
      (cons thumb :photo)))
    ))

(defun telega-ins--location-msg (msg)
  "Insert content for location message MSG."
  (let* ((content (plist-get msg :content))
         (loc (plist-get content :location))
         (loc-thumb (plist-get loc :telega-map-thumbnail)))
    (telega-ins--location loc)

    (if loc-thumb
        (progn
          (telega-ins "\n")
          (telega-ins--image-slices
           (telega-media--image
            (cons loc-thumb 'telega-thumb--create-image-as-is)
            (cons loc-thumb :photo))))

      ;; Get the map thumbnail
      (let ((zoom (nth 0 telega-location-thumb-params))
            (width (nth 1 telega-location-thumb-params))
            (height (nth 2 telega-location-thumb-params))
            (scale (nth 3 telega-location-thumb-params)))
        (telega--getMapThumbnailFile
            loc zoom width height scale (telega-msg-chat msg)
          (lambda (file)
            (telega-file--ensure file)
            ;; Generate pseudo thumbnail, suitable for
            ;; `telega-media--image'
            (plist-put loc :telega-map-thumbnail
                       (list :width width :height height :photo file))
            (telega-msg-redisplay msg)))))
    ))

(defun telega-ins--input-file (document &optional attach-symbol)
  "Insert input file."
  (telega-ins (or attach-symbol telega-symbol-attachment) " ")
  (cl-ecase (telega--tl-type document)
    (inputFileLocal
     (telega-ins (abbreviate-file-name (plist-get document :path))))
    (inputFileId
     (let ((preview (get-text-property
                     0 'telega-preview (plist-get document :@type))))
       (when preview
         (telega-ins--image preview)
         (telega-ins " ")))
     (telega-ins-fmt "Id: %d" (plist-get document :id))
     )
    (inputFileRemote
     ;; TODO: getRemoteFile
     (telega-ins-fmt "Remote: %s" (plist-get document :id))
     )
    ))

(defun telega-msg-special-p (msg)
  "Return non-nil if MSG is special."
  (memq (telega--tl-type (plist-get msg :content))
        (list 'messageContactRegistered 'messageChatAddMembers
              'messageChatJoinByLink 'messageChatDeleteMember
              'messageChatChangeTitle 'messageSupergroupChatCreate
              'messageBasicGroupChatCreate 'messageCustomServiceAction
              'messageChatSetTtl 'messageExpiredPhoto
              'messageChatChangePhoto 'messageChatUpgradeFrom
              'messagePinMessage)))

(defun telega-ins--special (msg)
  "Insert special message MSG.
Special messages are determined with `telega-msg-special-p'."
  (telega-ins "--(")
  (let* ((content (plist-get msg :content))
         (sender-id (plist-get msg :sender_user_id))
         (sender (unless (zerop sender-id) (telega-user--get sender-id))))
    (cl-case (telega--tl-type content)
      (messageContactRegistered
       (telega-ins (telega-user--name sender) " joined the Telegram"))
      (messageChatAddMembers
       ;; If sender matches
       (let ((user-ids (plist-get content :member_user_ids)))
         (if (and (= 1 (length user-ids))
                  (= (plist-get sender :id) (aref user-ids 0)))
             (telega-ins (telega-user--name sender 'name) " joined the group")
           (telega-ins (telega-user--name sender 'name) " invited "
                       (mapconcat 'telega-user--name
                                  (mapcar 'telega-user--get user-ids)
                                  ", ")))))
      (messageChatJoinByLink
       (telega-ins (telega-user--name sender)
                   " joined the group via invite link"))
      (messageChatDeleteMember
       (let ((user (telega-user--get (plist-get content :user_id))))
         (if (eq sender user)
             (telega-ins (telega-user--name user 'name) " left the group")
           (telega-ins (telega-user--name sender 'name)
                       " removed "
                       (telega-user--name user 'name)))))

      (messageChatChangeTitle
       (telega-ins "Renamed to \"" (plist-get content :title) "\"")
       (when sender
         (telega-ins " by " (telega-user--name sender 'short))))

      (messageSupergroupChatCreate
       (telega-ins (if (plist-get msg :is_channel_post)
                       "Channel" "Supergroup"))
       (telega-ins " \"" (plist-get content :title) "\" created"))
      (messageBasicGroupChatCreate
       (telega-ins "Group \"" (plist-get content :title) "\" created"))
      (messageCustomServiceAction
       (telega-ins (plist-get content :text)))
      (messageChatSetTtl
       (telega-ins-fmt "messages TTL set to %s"
         (telega-duration-human-readable (plist-get content :ttl))))
      (messageExpiredPhoto
       ;; I18N: lng_ttl_photo_expired
       (telega-ins "Photo has expired"))
      (messageChatChangePhoto
       (telega-ins "Group photo updated"))
      (messageChatUpgradeFrom
       (telega-ins (telega-user--name sender 'short)
                   " upgraded the group to supergroup"))
      (messagePinMessage
       (if sender
           (telega-ins (telega-user--name sender 'short))
         (telega-ins "Message"))
       (telega-ins " pinned \"")
       (let ((pin-msg (telega-msg--get (plist-get msg :chat_id)
                                       (plist-get content :message_id))))
         (telega-ins--with-attrs (list :min 20 :max 20
                                       :align 'left :elide t)
         (telega-ins--content-one-line pin-msg)))
       (telega-ins "\""))
      (t (telega-ins-fmt "<unsupported special message: %S>"
           (telega--tl-type content)))))
  (telega-ins ")--"))

(defun telega-ins--content (msg)
  "Insert message's MSG content."
  (let ((content (plist-get msg :content)))
    (pcase (telega--tl-type content)
      ('messageText
       (telega-ins--text (plist-get content :text))
       (telega-ins-prefix "\n"
         (telega-ins--webpage msg)))
      ('messageDocument
       (telega-ins--document msg))
      ('messagePhoto
       (telega-ins--photo (plist-get content :photo) msg))
      ('messageSticker
       (telega-ins--sticker-image (plist-get content :sticker) 'slices))
      ('messageAudio
       (telega-ins--audio msg))
      ('messageVideo
       (telega-ins--video msg))
      ('messageVoiceNote
       (telega-ins--voice-note msg))
      ('messageVideoNote
       (telega-ins--video-note msg))
      ('messageInvoice
       (telega-ins--invoice content))
      ('messageAnimation
       (telega-ins--animation-msg msg))
      ('messageLocation
       (telega-ins--location-msg msg))
      ('messageContact
       (telega-ins--contact-msg msg))
      ;; special message
      ((guard (telega-msg-special-p msg))
       (telega-ins--special msg))
      (_ (telega-ins-fmt "<TODO: %S>"
                         (telega--tl-type content))))

    (telega-ins-prefix "\n"
      (telega-ins--text (plist-get content :caption))))
  )

(defun telega-ins--inline-kbd (kbd-button msg)
  "Insert inline KBD-BUTTON for the MSG."
  (cl-case (telega--tl-type kbd-button)
    (inlineKeyboardButton
     (telega-ins--button (plist-get kbd-button :text)
       'action (lambda (ignored)
                 (telega-inline--callback kbd-button msg))
       :help-echo (telega-inline--help-echo kbd-button msg)))
    (t (telega-ins-fmt "<TODO: %S>" kbd-button))))

(defun telega-ins--reply-markup (msg)
  "Insert reply markup."
  (let ((reply-markup (plist-get msg :reply_markup)))
    (when reply-markup
      (cl-case (telega--tl-type reply-markup)
        (replyMarkupInlineKeyboard
         (let ((rows (plist-get reply-markup :rows)))
           (dotimes (ridx (length rows))
             (seq-doseq (but (aref rows ridx))
               (telega-ins--inline-kbd but msg)
               (telega-ins " "))
             (unless (= ridx (1- (length rows)))
               (telega-ins "\n")))))
        (t (telega-ins-fmt "<TODO reply-markup: %S>" reply-markup)))
      t)))

(defun telega-ins--aux-msg-inline (title msg face &optional with-username)
  "Insert REPLY-MSG as one-line."
  (when msg
    (telega-ins--with-attrs  (list :max (- telega-chat-fill-column
                                           (telega-current-column))
                                   :elide t
                                   :face face)
      (telega-ins "| " title ": ")
      (when (and with-username
                 (telega-ins--username (plist-get msg :sender_user_id)))
        (telega-ins "> "))
      (telega-ins--content-one-line msg)
      (when telega-msg-heading-whole-line
        (telega-ins "\n")))
    (unless telega-msg-heading-whole-line
      (telega-ins "\n"))
    ))

(defun telega-ins--aux-reply-inline (reply-msg &optional face)
  (telega-ins--aux-msg-inline
   "Reply" reply-msg (or face 'telega-chat-prompt) 'with-username))

(defun telega-ins--aux-edit-inline (edit-msg)
  (telega-ins--aux-msg-inline
   "Edit" edit-msg 'telega-chat-prompt))

(defun telega-ins--aux-fwd-inline (fwd-msg)
  (telega-ins--aux-msg-inline
   "Forward" fwd-msg 'telega-chat-prompt 'with-username))

(defun telega-ins--message-header (msg &optional no-avatar)
  "Insert message's MSG header, everything except for message content.
If NO-AVATAR is specified, then do not insert avatar."
  ;; twidth including 10 chars of date and 1 of outgoing status
  (let* ((fwidth (- telega-chat-fill-column (telega-current-column)))
         (twidth (+ 10 1 fwidth))
         (chat (telega-msg-chat msg))
         (sender (telega-msg-sender msg))
         (channel-post-p (plist-get msg :is_channel_post))
         (tfaces (list (if (telega-msg-by-me-p msg)
                           'telega-msg-self-title
                         'telega-msg-user-title))))
    (telega-ins--with-attrs (list :face 'telega-msg-heading
                                  :min fwidth :max twidth
                                  :align 'left :elide t)
      ;; Maybe add some rainbow color to the message title
      (when telega-msg-rainbow-title
        (let ((color (if channel-post-p
                         (telega-chat-color chat)
                       (telega-user-color sender)))
              (lightp (eq (frame-parameter nil 'background-mode) 'light)))
          (push (list :foreground (nth (if lightp 2 0) color)) tfaces)))
      (telega-ins--with-attrs (list :face tfaces)
        ;; Message title itself
        (if (not channel-post-p)
            (telega-ins (telega-user--name sender))
          (telega-ins (telega-chat-title chat 'with-username))
          (telega-ins-prefix " --"
            (telega-ins (plist-get msg :author_signature)))))

      (let ((views (plist-get msg :views)))
        (unless (zerop views)
          (telega-ins-fmt " %s %d" telega-symbol-eye views)))
      (telega-ins-prefix " edited at "
        (unless (zerop (plist-get msg :edit_date))
          (telega-ins--date (plist-get msg :edit_date))))
      (when telega-debug
        (telega-ins-fmt " (ID=%d)" (plist-get msg :id)))

      (when telega-msg-heading-whole-line
        (telega-ins "\n")))
    (unless telega-msg-heading-whole-line
      (telega-ins "\n"))
    ))

(defun telega-ins--fwd-info-inline (fwd-info)
  "Insert forward info FWD-INFO as one liner."
  (when fwd-info
    (telega-ins--with-props
        ;; When pressen, then jump to original message
        (list 'action
              (lambda (_button)
                (let ((chat-id (plist-get fwd-info :from_chat_id))
                      (msg-id (plist-get fwd-info :from_message_id)))
                  (when (and chat-id msg-id (not (zerop chat-id)))
                    (telega-chat--goto-msg (telega-chat-get chat-id) msg-id t)))))
      (telega-ins--with-attrs  (list :max (- telega-chat-fill-column
                                             (telega-current-column))
                                     :elide t
                                     :face 'telega-msg-inline-forward)
        (telega-ins "| Forwarded From: ")
        (let ((origin (plist-get fwd-info :origin)))
          (cl-ecase (telega--tl-type origin)
            (messageForwardOriginUser
             (let ((sender (telega-user--get (plist-get origin :sender_user_id))))
               (telega-ins (telega-user--name sender))))
            (messageForwardOriginHiddenUser
             (telega-ins (plist-get origin :sender_name)))
            (messageForwardOriginChannel
             (let ((chat (telega-chat-get (plist-get origin :chat_id)))
                   (signature (plist-get origin :author_signature)))
               (telega-ins (telega-chat-title chat 'with-username))
               (telega-ins-prefix " --"
                 (telega-ins signature))))))

        (let ((date (plist-get fwd-info :date)))
          (unless (zerop date)
            (telega-ins " at ")
            (telega-ins--date date)))
        (when telega-msg-heading-whole-line
          (telega-ins "\n")))
      (unless telega-msg-heading-whole-line
        (telega-ins "\n")))
    t))

(defun telega-ins--reply-inline (reply-to-msg)
  "Insert REPLY-TO-MSG as one liner."
  (when reply-to-msg
    (telega-ins--with-props
        ;; When pressen, then jump to the REPLY-TO-MSG message
        (list 'action
              (lambda (_button)
                (telega-msg-goto-highlight reply-to-msg)))
      (telega-ins--aux-reply-inline reply-to-msg 'telega-msg-inline-reply))))

(defun telega-ins--message (msg &optional no-header)
  "Insert message MSG.
If NO-HEADER is non-nil, then do not display message header
unless message is edited."
  (if (telega-msg-special-p msg)
      (telega-ins--with-attrs (list :min (- telega-chat-fill-column
                                            (telega-current-column))
                                    :align 'center
                                    :align-symbol "-")
        (telega-ins--content msg))

    ;; Message header needed
    (let* ((chat (telega-msg-chat msg))
           (sender (telega-msg-sender msg))
           (channel-post-p (plist-get msg :is_channel_post))
           (avatar (if channel-post-p
                       (telega-chat-avatar-image chat)
                     (telega-user-avatar-image sender)))
           (awidth (string-width (plist-get (cdr avatar) :telega-text)))
           ccol)
      (if (and no-header (zerop (plist-get msg :edit_date)))
          (telega-ins (make-string awidth ?\s))
        (telega-ins--image avatar 0)
        (telega-ins--message-header msg)
        (telega-ins--image avatar 1))

      (setq ccol (telega-current-column))
      (telega-ins--fwd-info-inline (plist-get msg :forward_info))
      (telega-ins--reply-inline (telega-msg-reply-msg msg))
      (telega-ins--column ccol telega-chat-fill-column
        (telega-ins--content msg)
        (telega-ins-prefix "\n"
          (telega-ins--reply-markup msg)))))

  ;; Date/status starts at `telega-chat-fill-column' column
  (let ((slen (- telega-chat-fill-column (telega-current-column))))
    (when (< slen 0) (setq slen 1))
    (telega-ins (make-string slen ?\s)))
  (telega-ins--with-attrs (list :align 'right :min 10)
    (telega-ins--date (plist-get msg :date)))
  (telega-ins--outgoing-status msg)
  t)

(defun telega-ins--input-content-one-line (imc)
  "Insert input message's MSG content for one line usage."
  (telega-ins--one-lined
   (cl-case (telega--tl-type imc)
     (inputMessageLocation
      (telega-ins--location (plist-get imc :location))
      (when (> (or (plist-get imc :live_period) 0) 0)
        (telega-ins " Live for: "
                    (telega-duration-human-readable
                     (plist-get imc :live_period)))))
     (inputMessageContact
      (telega-ins--contact (plist-get imc :contact)))
     (inputMessageDocument
      (telega-ins--input-file (plist-get imc :document)))
     (inputMessagePhoto
      (telega-ins--input-file (plist-get imc :photo) telega-symbol-photo))
     (inputMessageAudio
      (telega-ins--input-file (plist-get imc :audio) telega-symbol-audio))
     (inputMessageVideo
      (telega-ins--input-file (plist-get imc :video) telega-symbol-video))
     (inputMessageSticker
      (telega-ins--input-file (plist-get imc :sticker) "Sticker"))
     (inputMessageAnimation
      (telega-ins--input-file (plist-get imc :animation) "Animation"))
     (t
      (telega-ins-fmt "<TODO: %S>" (telega--tl-type imc)))
     )))

(defun telega-ins--content-one-line (msg)
  "Insert message's MSG content for one line usage."
  (telega-ins--one-lined
   (let ((content (plist-get msg :content)))
     (cl-case (telega--tl-type content)
       (messageText
        (telega-ins--text (plist-get content :text)))
       (messagePhoto
        (telega-ins telega-symbol-photo " ")
        (or (telega-ins--text (plist-get content :caption))
            ;; I18N: lng_in_dlg_photo or lng_attach_photo
            (telega-ins (propertize "Photo" 'face 'shadow))))
       (messageDocument
        (telega-ins telega-symbol-attachment " ")
        (or (telega-ins (telega--tl-get content :document :file_name))
            (telega-ins--text (plist-get content :caption))
            (telega-ins (propertize "Document" 'face 'shadow))))
       (messageLocation
        (telega-ins telega-symbol-location " ")
        (let ((loc (plist-get content :location)))
          (telega-ins-fmt "%fN, %fE"
            (plist-get loc :latitude) (plist-get loc :longitude)))

        ;; NOTE: in case of unexpired live location show last update
        ;; time and expiration period
        (let ((live-period (plist-get content :live_period)))
          (unless (zerop live-period)
            (telega-ins " " (propertize "Live" 'face 'shadow))
            (unless (zerop (plist-get content :expires_in))
              (let* ((current-ts (truncate (float-time)))
                     (since (if (zerop (plist-get msg :edit_date))
                                (plist-get msg :date)
                              (plist-get msg :edit_date)))
                     (live-for (- (+ since live-period) current-ts)))
                (when (> live-for 0)
                  (telega-ins-fmt " for %s"
                    (telega-duration-human-readable live-for))
                  (telega-ins-fmt " (updated %s ago)"
                    (telega-duration-human-readable
                     (- current-ts since)))))))))
       (messageAnimation
        (or (telega-ins--text (plist-get content :caption))
            (telega-ins (propertize "GIF" 'face 'shadow))))
       (messageAudio
        (telega-ins telega-symbol-audio " ")
        (or (telega-ins--text (plist-get content :caption))
            (telega-ins (propertize "Audio" 'face 'shadow)))
        (telega-ins-fmt " (%s)"
          (telega-duration-human-readable
           (telega--tl-get content :audio :duration))))
       (messageVideo
        (telega-ins telega-symbol-video " ")
        (or (telega-ins--text (plist-get content :caption))
            (telega-ins (propertize "Video" 'face 'shadow)))
        (telega-ins-fmt " (%s)"
          (telega-duration-human-readable
           (telega--tl-get content :video :duration))))
       (messageGame
        (telega-ins telega-symbol-game " ")
        (or (telega-ins (telega--tl-get content :game :title))
            (telega-ins (telega--tl-get content :game :short_name))
            (telega-ins (propertize "Game" 'face 'shadow))))
       (messageSticker
        (telega-ins (telega--tl-get content :sticker :emoji))
        (telega-ins " " (propertize "Sticker" 'face 'shadow)))
       (messageCall
        (telega-ins telega-symbol-phone " ")
        (let* ((reason (telega--tl-type (plist-get content :discard_reason)))
               (label (cond ((plist-get msg :is_outgoing)
                             (if (eq reason 'callDiscardReasonMissed)
                                 "Cancelled call" ;; I18N: lng_call_cancelled
                               "Outgoing call")) ;; I18N: lng_call_outgoing
                            ((eq reason 'callDiscardReasonMissed)
                             "Missed call") ;; I18N: lng_call_missed
                            ((eq reason 'callDiscardReasonDeclined)
                             "Declined call") ;; I18N: lng_call_declined
                            (t
                             "Incoming call")))) ;; I18N: lng_call_incoming
          (telega-ins (propertize label 'face 'shadow)))
        (telega-ins-fmt " (%s)"
          (telega-duration-human-readable
           (plist-get content :duration))))
       (messageVoiceNote
        ;; I18N: lng_in_dlg_audio
        (telega-ins (propertize "Voice message" 'face 'shadow))
        (telega-ins-fmt " (%s)"
          (telega-duration-human-readable
           (telega--tl-get content :voice_note :duration))))
       (messageVideoNote
        ;; I18N: lng_in_dlg_video_message
        (telega-ins (propertize "Video message" 'face 'shadow))
        (telega-ins-fmt " (%s)"
          (telega-duration-human-readable
           (telega--tl-get content :video_note :duration))))
       (messageContact
        ;; I18N: lng_in_dlg_contact
        (telega-ins (propertize "Contact" 'face 'shadow))
        (telega-ins-fmt " %s (%s %s)"
          (telega--tl-get content :contact :phone_number)
          (telega--tl-get content :contact :first_name)
          (telega--tl-get content :contact :last_name)))
       (messageInvoice
        (telega-ins (propertize "Invoice" 'face 'shadow))
        (telega-ins-prefix " "
          (telega-ins (plist-get content :title))))
       (t (telega-ins--content msg))))))


;; Inserter for custom filter button
(defun telega-ins--filter (custom)
  "Inserter for the CUSTOM filter button in root buffer."
  (let* ((name (car custom))
         (telega-filters--inhibit-list '(has-order))
         (chats (telega-filter-chats (cdr custom) telega--filtered-chats))
         (active-p (not (null chats)))
         (nchats (length chats))
         (unread (apply #'+ (mapcar (telega--tl-prop :unread_count) chats)))
         (mentions (apply #'+ (mapcar
                               (telega--tl-prop :unread_mention_count) chats)))
         (umwidth 7)
         (title-width (- telega-filter-button-width umwidth)))
    (telega-ins--with-props (list 'inactive (not active-p)
                                  'face (if active-p
                                            'telega-filter-button-active
                                          'telega-filter-button-inactive)
                                  'action (if active-p
                                              'telega-filter-button--action
                                            'ignore))
      (telega-ins "[")
      (telega-ins--with-attrs (list :min title-width
                                    :max title-width
                                    :elide t
                                    :align 'left)
        (telega-ins-fmt "%d:%s" nchats name))
      (telega-ins--with-attrs (list :min umwidth
                                    :max umwidth
                                    :elide t
                                    :align 'right)
        (unless (zerop unread)
          (telega-ins-fmt "%d" unread))
        (unless (zerop mentions)
          (telega-ins-fmt "@%d" mentions)))
      (telega-ins "]"))))


(defun telega-ins--chat-msg-one-line (chat msg max-width)
  "Insert message for the chat button usage."
  (cl-assert (> max-width 11))
  ;; NOTE: date - 10 chars, outgoing-status - 1 char
  (telega-ins--with-attrs (list :align 'left
                                :min (- max-width 10 1)
                                :max (- max-width 10 1)
                                :elide t)
    ;; NOTE: Do not show username for:
    ;;  - Saved Messages
    ;;  - If sent by user in private/secret chat
    ;;  - Special messages
    (unless (or (eq (plist-get msg :sender_user_id)
                    (plist-get chat :id))
                (telega-chat--secret-p chat)
                (telega-msg-special-p msg))
      (when (telega-ins--username (plist-get msg :sender_user_id))
        (telega-ins ": ")))

    (telega-ins--content-one-line msg))

  (telega-ins--with-attrs (list :align 'right :min 10)
    (telega-ins--date (plist-get msg :date)))
  (telega-ins--outgoing-status msg)
  )

(defun telega-ins--chat (chat &optional brackets)
  "Inserter for CHAT button in root buffer.
BRACKETS is cons cell of open-close brackets to use.
By default BRACKETS is choosen according to `telega-chat-button-brackets'.

Return t."
  (let ((title (telega-chat-title chat))
        (unread (plist-get chat :unread_count))
        (mentions (plist-get chat :unread_mention_count))
        (pinned-p (plist-get chat :is_pinned))
        (custom-order (telega-chat-uaprop chat :order))
        (muted-p (telega-chat--muted-p chat))
        (chat-info (telega-chat--info chat))
        (chat-ava (plist-get chat :telega-avatar-1)))
    (when (plist-get chat-info :is_verified)
      (setq title (concat title telega-symbol-verified)))
    (when (telega-chat--secret-p chat)
      (setq title (propertize title 'face 'telega-secret-title)))
    (unless brackets
      (setq brackets (cdr (seq-find (lambda (bspec)
                                      (telega-filter-chats
                                       (car bspec) (list chat)))
                                    telega-chat-button-brackets))))

    (telega-ins (or (car brackets) "["))

    ;; 1) First we format unread@mentions as string to find out its
    ;;    final length
    ;; 2) Then we insert the title as wide as possible
    ;; 3) Then insert formatted UNREAD@MENTIONS string
    (let* ((umstring (telega-ins--as-string
                      (unless (zerop unread)
                        (telega-ins--with-face (if muted-p
                                                   'telega-muted-count
                                                 'telega-unmuted-count)
                          (telega-ins (number-to-string unread))))
                      (unless (zerop mentions)
                        (telega-ins--with-face 'telega-mention-count
                          (telega-ins-fmt "@%d" mentions)))
                      ;; Mark for chats marked as unread
                      (when (and (zerop unread) (zerop mentions)
                                 (plist-get chat :is_marked_as_unread))
                        (telega-ins--with-face (if muted-p
                                                   'telega-muted-count
                                                 'telega-unmuted-count)
                          (telega-ins telega-symbol-unread)))
                      ;; For chats searched by
                      ;; `telega--searchPublicChats' insert number of
                      ;; members in the group
                      ;; Basicgroups converted to supergroups
                      ;; does not have username and have "0" order
                      (when (string= "0" (plist-get chat :order))
                        (when (telega-chat-username chat)
                          (telega-ins--with-face 'telega-username
                            (telega-ins "@" (telega-chat-username chat))))
                        (telega-ins--with-face (if muted-p
                                                   'telega-muted-count
                                                 'telega-unmuted-count)
                          (cl-case (telega-chat--type chat 'no-interpret)
                            (basicgroup
                             (telega-ins telega-symbol-contact
                                         (number-to-string
                                          (plist-get chat-info :member_count))))
                            (supergroup
                             (telega-ins telega-symbol-contact
                                         (number-to-string
                                          (plist-get
                                           (telega--full-info chat-info)
                                           :member_count)))))))
                      ))
           (title-width (- telega-chat-button-width (string-width umstring))))
      (telega-ins--with-attrs (list :min title-width
                                    :max title-width
                                    :align 'left
                                    :elide t)
        (when chat-ava
          (telega-ins--image chat-ava))
        (telega-ins title))
      (telega-ins umstring))

    (telega-ins (or (cadr brackets) "]"))
    (when pinned-p
      (telega-ins telega-symbol-pin))
    (when custom-order
      (telega-ins
       (if (< (string-to-number custom-order)
              (string-to-number (plist-get chat :order)))
           (car telega-symbol-custom-order)
         (cdr telega-symbol-custom-order))))
    (when (telega-chat--secret-p chat)
      (telega-ins telega-symbol-lock))
    t))

(defun telega-ins--chat-full (chat)
  "Full status inserter for CHAT button in root buffer."
  (telega-ins--chat chat)
  (telega-ins "  ")

  ;; And the status
  (let ((max-width (- telega-root-fill-column (current-column)))
        (actions (gethash (plist-get chat :id) telega--actions))
        (call (telega-voip--by-user-id (plist-get chat :id)))
        (draft-msg (plist-get chat :draft_message))
        (last-msg (plist-get chat :last_message))
        (chat-info (telega-chat--info chat)))
    (cond ((and (telega-chat--secret-p chat)
                (memq (telega--tl-type (plist-get chat-info :state))
                      '(secretChatStatePending secretChatStateClosed)))
           ;; Status of the secret chat
           (telega-ins (propertize
                        (substring (telega--tl-get chat-info :state :@type) 15)
                        'face 'shadow)))

          (call
           (let ((state (plist-get call :state)))
             (telega-ins telega-symbol-phone " ")
             (telega-ins-fmt "%s Call (%s)"
               (if (plist-get call :is_outgoing) "Outgoing" "Incoming")
               (substring (plist-get state :@type) 9))

             (when (eq (telega--tl-type state) 'callStateReady)
               (telega-ins " " (telega-voip--call-emojis call)))
             ))

           (actions
           (telega-debug "CHAT-ACTIONS: %s --> %S"
                         (telega-chat-title chat) actions)
           (telega-ins--with-attrs (list :align 'left
                                         :max max-width
                                         :elide t)
             (telega-ins--actions actions)))

          (draft-msg
           (let ((inmsg (plist-get draft-msg :input_message_text)))
             (cl-assert (eq (telega--tl-type inmsg) 'inputMessageText) nil
                        "tdlib states that draft must be `inputMessageText'")
             (telega-ins--with-attrs (list :align 'left
                                           :max max-width
                                           :elide t)
               (telega-ins telega-symbol-draft ": ")
               (telega-ins--one-lined
                (telega-ins--text (plist-get inmsg :text))))))

          (last-msg
           (telega-ins--chat-msg-one-line chat last-msg max-width))

          ((and (telega-chat--secret-p chat)
                (eq (telega--tl-type (plist-get chat-info :state))
                    'secretChatStateReady))
           ;; Status of the secret chat
           (telega-ins (propertize
                        (substring (telega--tl-get chat-info :state :@type) 15)
                        'face 'shadow)))
          ))
  t)

(defun telega-ins--root-msg (msg)
  "Inserter for message MSG shown in `telega-root-messages--ewoc'."
  (let ((chat (telega-msg-chat msg))
        (telega-chat-button-width (* 2 (/ telega-chat-button-width 3))))
    (telega-ins--chat chat)
    (telega-ins "  ")
    (let ((max-width (- telega-root-fill-column (current-column))))
      (telega-ins--chat-msg-one-line chat msg max-width))))

(provide 'telega-ins)

;;; telega-ins.el ends here
