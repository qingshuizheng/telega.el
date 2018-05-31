;;; telega-msg.el --- Messages for telega

;; Copyright (C) 2018 by Zajcev Evgeny.

;; Author: Zajcev Evgeny <zevlg@yandex.ru>
;; Created: Fri May  4 03:49:22 2018
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

;;

;;; Code:
(require 'telega-core)
(require 'telega-customize)

(defvar telega-msg-button-keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map button-map)
    (define-key map [remap self-insert-command] 'ignore)
    (define-key map (kbd "i") 'telega-msg-info)
    (define-key map (kbd "n") 'telega-button-forward)
    (define-key map (kbd "p") 'telega-button-backward)
    (define-key map (kbd "r") 'telega-msg-reply)
    (define-key map (kbd "e") 'telega-msg-edit)
    (define-key map (kbd "f") 'telega-msg-forward)
    (define-key map (kbd "DEL") 'telega-msg-delete)
    map))

(define-button-type 'telega-msg
  :supertype 'telega
  :prev-msg nil                         ; previous message
  'keymap telega-msg-button-keymap
  'action #'telega-msg-reply)

(defsubst telega-msg--chat (msg)
  "Return chat for the MSG."
  (telega-chat--get (plist-get msg :chat_id)))

(defun telega-msg--get (chat-id msg-id)
  "Get message by CHAT-ID and MSG-ID pair."
  ;; Optimisation for formatting messages with reply
  (or (with-telega-chat-buffer (telega-chat--get chat-id)
        (cl-find msg-id telega-chatbuf--replies
                 :test (lambda (msg-id reply-msg)
                         (= msg-id (plist-get reply-msg :id)))))

      (telega-server--call
       (list :@type "getMessage"
             :chat_id chat-id
             :message_id msg-id))))

(defun telega-msg--get-link (chat-id msg-id &optional for-album)
  "Get https link to public message."
  (telega-server--call
   (list :@type "getPublicMessageLink"
         :chat_id chat-id
         :message_id msg-id
         :for_album (or for-album :json-false))))

(defun telega-msg-chat-title (msg)
  "Title of the message's chat."
  (telega-chat--title (telega-msg--chat msg) 'with-username))

(defun telega-msg-sender-shortname (msg &optional suffix)
  "Short name of the MSG sender."
  (let ((sender-uid (plist-get msg :sender_user_id)))
    (unless (zerop sender-uid)
      (concat (telega-user--name (telega-user--get sender-uid) 'short)
              (or suffix "")))))

(defun telega-msg-sender-name (msg)
  "Title of the MSG sender."
  (let ((sender-uid (plist-get msg :sender_user_id)))
    (unless (zerop sender-uid)
      (telega-user--name (telega-user--get sender-uid)))))

(defun telega-msg-sender-ava-h (msg)
  "High stripe of the MSG sender's avatar."
  ;; TODO: sender avatar high stripe
  (let ((sender-uid (plist-get msg :sender_user_id)))
    (unless (zerop sender-uid)
      (let* ((user (telega-user--get sender-uid))
             (ufn (plist-get user :first_name))
             (uln (plist-get user :last_name))
             (res ""))
        (unless (string-empty-p ufn)
          (setq res (capitalize (substring ufn 0 1))))
        (unless (string-empty-p uln)
          (setq res (concat res (capitalize (substring uln 0 1)))))
        (when (= 1 (length res))
          (setq res (concat res res)))
        (concat "(" res ")")))))

(defun telega-msg-sender-ava-l (msg)
  "Low stripe of the MSG sender's avatar."
  ;; TODO: sender avatar low stripe
  (let ((sender-uid (plist-get msg :sender_user_id)))
    (unless (zerop sender-uid)
      "    ")))

(defun telega-msg-timestamp (msg)
  "Format MSG date."
  (telega-fmt-timestamp (plist-get msg :date)))

(defun telega-msg-outgoing-status (msg)
  "Outgoing status of the message."
  (when (telega--tl-bool msg :is_outgoing)
    (let ((sending-state (plist-get (plist-get msg :sending_state) :@type))
          (chat (telega-chat--get (plist-get msg :chat_id))))
    (cond ((and (stringp sending-state)
                (string= sending-state "messageSendingStatePending"))
           telega-symbol-msg-pending)
          ((and (stringp sending-state)
                (strintg= sending-state "messageSendingStateFailed"))
           telega-symbol-msg-failed)
          ((>= (plist-get chat :last_read_outbox_message_id)
               (plist-get msg :id))
           telega-symbol-msg-viewed)
          (t telega-symbol-msg-succeed)))))

(defun telega-msg-text-with-props (msg)
  "Return formatted text for the MSG."
  (let ((content (plist-get msg :content)))
    (case (telega--tl-type content)
      (messageText
       (let ((text (plist-get content :text)))
         (telega-msg--ents-to-props
          (plist-get text :text)
          (plist-get text :entities))))
      (t (format "<unsupported message %S>" (telega--tl-type content))))))

(defun telega-msg-text-with-props-one-line (msg)
  "Format MSG's text as one line."
  (replace-regexp-in-string "\n" " " (telega-msg-text-with-props msg)))

(defun telega-msg-button--format-error (msg)
  (error "Must set :format explicitly for message buttons."))

(defun telega-msg-button--format-one-line (msg)
  "Format message MSG to be displayed in one line."
  (list (telega-msg-sender-shortname msg "> ")
        'telega-msg-text-with-props-one-line))

(defun telega-msg-sender-admin-status (msg)
  (let ((admins-tl (telega-server--call
                    (list :@type "getChatAdministrators"
                          :chat_id (plist-get msg :chat_id)))))
    (when (cl-find (plist-get msg :sender_user_id)
                   (plist-get admins-tl :user_ids)
                   :test #'=)
      " (admin)")))

(defun telega-msg-sender-status (msg)
  "Format MSG sender status.
Makes heave online requests without caching, be carefull."
  (let ((ucm (telega-server--call
              (list :@type "getChatMember"
                    :chat_id (plist-get msg :chat_id)
                    :user_id (plist-get msg :sender_user_id)))))
    (telega-fmt-chat-member-status (plist-get ucm :status))))

(defun telega-msg-via-bot (msg)
  (let ((via-bot-id (plist-get msg :via_bot_user_id)))
    (unless (zerop via-bot-id)
      (concat " via @" (plist-get (telega-user--get via-bot-id) :username)))))

(defun telega-msg-edit-date (msg)
  (let ((edit-date (plist-get msg :edit_date)))
    (unless (zerop edit-date)
      (concat " edited at " (telega-fmt-timestamp edit-date)))))

(defun telega-msg-inline-reply (msg fill-prefix)
  (let* ((reply-to-msg-id (plist-get msg :reply_to_message_id))
         (reply-msg (unless (zerop reply-to-msg-id)
                      (telega-msg--get (plist-get msg :chat_id)
                                       reply-to-msg-id))))
    (when reply-msg
      `((("| Reply: " ,(telega-fmt-eval
                        (telega-msg-button--format-one-line reply-msg)
                        reply-msg))
         :max ,(- telega-chat-fill-column (length fill-prefix))
         :face telega-chat-inline-reply)
        "\n" ,fill-prefix))))

(defun telega-msg-text-with-timestamp (msg fill-prefix)
  `((telega-msg-text-with-props
     :fill left
     :fill-prefix ,fill-prefix
     :fill-column ,telega-chat-fill-column
     :min ,telega-chat-fill-column
     :align left)
    (telega-msg-timestamp :align right :min 10)
    (telega-msg-outgoing-status :face telega-msg-status)
    "\n"))

(defun telega-msg-button--format-channel (msg)
  `((telega-msg-chat-title :face telega-chat-user-title)
    telega-msg-via-bot
    " " ,telega-symbol-eye " " ,(plist-get msg :views)
    telega-msg-edit-date
    "\n"
    ,@(telega-msg-inline-reply msg "")
    ,@(telega-msg-text-with-timestamp msg "")))

(defconst telega-msg-full-prefix "     ")

(defun telega-msg-button--format-full (msg &optional reply-msg)
  `(telega-msg-sender-ava-h
    " "
    (telega-msg-sender-name
     :face ,(if (= (plist-get msg :sender_user_id) telega--me-id)
                'telega-chat-self-title
              'telega-chat-user-title))
    ,(when telega-msg-show-sender-status
       '(telega-msg-sender-status :face shadow))
    telega-msg-via-bot
    telega-msg-edit-date
    "\n"
    telega-msg-sender-ava-l " "
    ,@(telega-msg-inline-reply msg telega-msg-full-prefix)
    ,@(telega-msg-text-with-timestamp msg telega-msg-full-prefix)))

(defun telega-msg-button--format-same (msg)
  "Fromat message when previous msg is from the same sender."
  `(,telega-msg-full-prefix
    ,@(telega-msg-inline-reply msg telega-msg-full-prefix)
    ,@(telega-msg-text-with-timestamp msg telega-msg-full-prefix)))

(defun telega-msg-button--format-action (msg)
  "Format chat's action message, such as messageChatAddMembers."
  (let ((content (plist-get msg :content)))
    `((("--(" ,(case (telega--tl-type content)
                 (messageChatAddMembers
                  (concat
                   (mapconcat 'telega-user--name
                              (mapcar 'telega-user--get
                                      (plist-get content :member_user_ids))
                              ", ")
                   " joined the group"))
                 (messageChatDeleteMember
                  (concat (telega-user--name
                           (telega-user--get (plist-get content :user_id)))
                          " left the group"))
                 (messageChatChangeTitle
                  (concat (telega-user--name
                           (telega-user--get (plist-get msg :sender_user_id)))
                          " renamed group to \"" (plist-get content :title) "\""))
                 (t "<unsupported chat action: %S>" (telega--tl-type content)))
        ")--")
       :min ,telega-chat-fill-column
       :align center
       :align-char ?\-)
      (telega-msg-timestamp :align right :min 10)
      "\n")))

(defun telega-msg-button--format (msg &optional prev-msg)
  "Produce fmt spec for the message MSG.
PREV-MSG is non-nil if there any previous message exists."
  (cond ((telega--tl-bool msg :is_channel_post)
         (telega-msg-button--format-channel msg))

        ((memq (telega--tl-type (plist-get msg :content))
               '(messageChatAddMembers messageChatDeleteMember messageChatChangeTitle))
         (telega-msg-button--format-action msg))

        (t (if (and prev-msg
                    (zerop (plist-get msg :edit_date))
                    (= (plist-get msg :sender_user_id)
                       (plist-get prev-msg :sender_user_id))
                    (string= (telega-msg-via-bot msg)
                             (telega-msg-via-bot prev-msg)))
               (telega-msg-button--format-same msg)
             (telega-msg-button--format-full msg)))))

(defsubst telega-msg-button--format-aux (title &optional msg)
  `((("| " ,title ": " telega-msg-button--format-one-line)
     :max ,telega-chat-fill-column
     :elide t
     :face telega-chat-prompt)
    "\n"))

(defun telega-msg-button--format-aux-reply (msg)
  (telega-msg-button--format-aux "Reply" msg))

(defun telega-msg-button--format-aux-edit (msg)
  (telega-msg-button--format-aux "Edit" msg))

(defun telega-msg--entity-to-properties (entity text)
  (let ((ent-type (plist-get entity :type)))
    (case (telega--tl-type ent-type)
      (textEntityTypeMention
       (list 'face 'telega-entity-type-mention))
      (textEntityTypeMentionName
       (list 'action 'telega-open-link-action
             'face 'telega-entity-type-mention
             :telega-link (cons 'user (plist-get ent-type :user_id))))
      (textEntityTypeHashtag
       (list 'action 'telega-open-link-action
             'face 'telega-entity-type-hashtag
             :telega-link (cons 'hashtag text)))
      (textEntityTypeBold
       (list 'face 'telega-entity-type-bold))
      (textEntityTypeItalic
       (list 'face 'telega-entity-type-italic))
      (textEntityTypeCode
       (list 'face 'telega-entity-type-code))
      (textEntityTypePre
       (list 'face 'telega-entity-type-pre))
      (textEntityTypePreCode
       (list 'face 'telega-entity-type-pre))

      (textEntityTypeUrl
       (list 'follow-link t
             'action 'telega-open-link-action
             'face 'telega-entity-type-texturl
             :telega-link (cons 'url text)))

      (textEntityTypeTextUrl
       (list 'follow-link t
             'action 'telega-open-link-action
             'face 'telega-entity-type-texturl
             :telega-link (cons 'url (plist-get ent-type :url))))
      )))

(defun telega-msg--ents-to-props (text entities)
  "Convert message TEXT with text ENTITIES to propertized string."
  (mapc (lambda (ent)
          (let* ((beg (plist-get ent :offset))
                 (end (+ (plist-get ent :offset) (plist-get ent :length)))
                 (props (telega-msg--entity-to-properties
                         ent (substring text beg end))))
            (when props
              (add-text-properties beg end props text))))
        entities)
  text)

(defun telega-msg--props-to-ents (text)
  "Convert propertiezed TEXT to message with text entities."
  ;; TODO: convert text properties to tl text entities
  (let ((entities))
    (cons text entities)))

(defun telega-msg-format (msg)
  (plist-get (plist-get (plist-get msg :content) :text) :text)
  )

(defun telega-msg--input-content (text &optional markdown)
  "Convert TEXT to tl InputMessageContent.
If MARKDOWN is non-nil then format TEXT as markdown."
  (let ((fmt-text (if markdown
                      (telega-server--call
                       (list :@type "parseTextEntities"
                             :text text
                             :parse_mode (list :@type "textParseModeMarkdown")))
                    (list :@type "formattedText"
                          :text text :entities []))))
    (list :@type "inputMessageText"
          :text fmt-text
          :clear_draft t)))


(defun telega-msg-info (msg)
  "Show info about message at point."
  (interactive (list (button-get (button-at (point)) :value)))
  (unless msg
    (error "No message at point"))

  (with-help-window " *Telegram Message Info*"
    (set-buffer standard-output)
    (let ((chat-id (plist-get msg :chat_id))
          (msg-id (plist-get msg :id)))
      (insert (format "Date(ISO8601): %s\n"
                      (format-time-string "%FT%T%z" (plist-get msg :date))))
      (insert (format "Chat-id: %d\n" chat-id))
      (insert (format "Message-id: %d\n" msg-id))
      (let ((sender-uid (plist-get msg :sender_user_id)))
        (unless (zerop sender-uid)
          (insert "Sender: ")
          (insert-text-button (telega-user--name (telega-user--get sender-uid))
                              :telega-link (cons 'user sender-uid))
          (insert "\n")))
      (when (telega-chat--public-p (telega-chat--get chat-id))
        (let ((link (plist-get (telega-msg--get-link chat-id msg-id) :link)))
          (insert "Link: ")
          (insert-text-button link :telega-link (cons 'url link)
                              'action 'telega-open-link-action)
          (insert "\n")))

      (when telega-debug
        (insert (format "MsgSexp: (telega-msg--get %d %d)\n" chat-id msg-id)))

      (insert (format "\nTODO: %S\n" msg)))
    ))

(defun telega-msg-reply (button)
  "Reply to the message at point."
  (interactive (list (button-at (point))))
  (telega-chat-msg-reply (button-get button :value)))

(defun telega-msg-edit (button)
  "Edit message at point."
  (interactive (list (button-at (point))))
  (telega-chat-msg-edit (button-get button :value)))

(provide 'telega-msg)

;;; telega-msg.el ends here
