import cv2
from ultralytics import YOLO
import mediapipe as mp
from transformers import pipeline
from PIL import Image
import numpy as np
import math
from sentence_transformers import SentenceTransformer, util

# all model configs
sentance_model = SentenceTransformer('all-MiniLM-L6-v2')
# yolo model
model = YOLO("yolov8l.pt") 

# depthestimator model also note to SAMMY if running this from ur computer change device to 'cuda' i only put cpu cuz mine isnt powerful enough
depth_estimator = pipeline(task="depth-estimation", model="depth-anything/Depth-Anything-V2-Small-hf", device='mps')
# SAMMY PLEASE READ THIS ONE COMMENT

# hand tracker model
mp_hands = mp.solutions.hands
hands = mp_hands.Hands(static_image_mode=False,
                       max_num_hands=2,
                       min_detection_confidence=0.5,
                       min_tracking_confidence=0.5)
mp_drawing = mp.solutions.drawing_utils
# model configs done

# get desired object
i = input('gimme da object')
query_embedding = sentance_model.encode(i, convert_to_tensor=True)
# get webcam
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("Error: Could not open webcam.")
    exit()

# function for full thing which is called upon wanting to find an object
def handtoobjectfinder():
    name = ''
    directions = ["Right", "Up-Right", "Up", "Up-Left", 
     "Left", "Down-Left", "Down", "Down-Right"]
    while True:
        ret, frame = cap.read()
        if not ret:
            print("Error: Failed to capture frame.")
            break

    # Convert the frame to RGB
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        pil_frame = Image.fromarray(rgb_frame)
    # Run Mediapipe Hands on the frame
        hand_results = hands.process(rgb_frame)

    # Run YOLO model on the frame
        yolo_results = model(frame)

        # Run depth-estimation model on the frame
        depth_result = depth_estimator(pil_frame)
        depth_map = np.array(depth_result['depth'])  # Extract the depth map (as a NumPy array)

    # Normalize the depth map for visualization (scale to 0-255)
        normalized_depth = cv2.normalize(depth_map, None, 0, 255, cv2.NORM_MINMAX).astype('uint8')
        depth_colored = cv2.applyColorMap(normalized_depth, cv2.COLORMAP_MAGMA)  # Colorize for better visualization

        c = 0
        things = []
        x1s, y1s, x2s, y2s = 0, 0, 0, 0
    # Draw YOLO detections
        for box in yolo_results[0].boxes:
            class_id = int(box.cls)
            label = model.names[class_id]

    # no ppl and ppl counter
            if class_id == 0:
                c += 1
                continue

    # Get box coordinates
            x1, y1, x2, y2 = map(int, box.xyxy[0])  # Bounding box coordinates
            if name == label:
                x1s, y1s, x2s, y2s = x1, y1, x2, y2
    

    # Draw bounding box
            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)

    # Put label and confidence text
            text = f"{label}"
            cv2.putText(frame, text, (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
            things = things + [model.names[class_id]]
        # this makes vector vector used later for direction
        if things != []:
            doc_embeddings = sentance_model.encode(things, convert_to_tensor=True)
            cosine_scores = util.cos_sim(query_embedding, doc_embeddings)[0] 
            ranked_docs = sorted(zip(cosine_scores.tolist(), things), reverse=True, key=lambda x: x[0])
            score, name = ranked_docs[0]
        object_x = (x1s + x2s) // 2
        object_y = (y1s + y2s) // 2
        

    # HANDS
        if hand_results.multi_hand_landmarks:
            for hand_landmarks in hand_results.multi_hand_landmarks:
                mp_drawing.draw_landmarks(
                    frame,
                    hand_landmarks,
                    mp_hands.HAND_CONNECTIONS,
                    mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2),
                    mp_drawing.DrawingSpec(color=(0, 0, 255), thickness=2, circle_radius=2),
            )
        if hand_results.multi_hand_landmarks and len(yolo_results[0].boxes) - c != 0:
            hand_landmarks = hand_results.multi_hand_landmarks[0]
            hand_x = int(hand_landmarks.landmark[mp_hands.HandLandmark.WRIST].x * 640)
            hand_y = int(hand_landmarks.landmark[mp_hands.HandLandmark.WRIST].y * 480)
            dx = object_x - hand_x
            dy = object_y - hand_y
            angle_radians = math.atan2(dy, dx)
            angle_radians = (angle_radians + math.pi) % (2 * math.pi) - math.pi
            angleindex = round((angle_radians + math.pi) / (math.pi / 4)) % 8
            dist = math.sqrt((object_x - hand_x)**2 + (object_y - hand_y)**2)
            if hand_y < 460 and hand_x < 620:
                obd, handd = depth_map[object_y,object_x], depth_map[hand_y,hand_x]
                print(obd,handd)
                if abs(int(handd) - int(obd)) >= 80:
                    print('go forward')
                elif (abs(int(handd) - int(obd)) <= 30) and dist <= 150:
                    print('object within reach')
                else: print(directions[angleindex])
            cv2.line(frame, (hand_x, hand_y), (object_x, object_y), (255, 0, 0), 2)
            print(dist)



        # IMPORTANT REMEMBER THIS
        combined_frame = cv2.addWeighted(frame, 0.6, depth_colored, 0.4, 0)  # Blend annotations with depth
        # UNCOMMENTING THIS WILL BRING DEPTH COLOR BACK TO DEMO
    # Display the annotated frame
        cv2.imshow("YOLO + Mediapipe Hands Tracking", combined_frame)

    # Break the loop if 'q' is pressed
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break


handtoobjectfinder()

# Release resources to exit the camera
cap.release()
cv2.destroyAllWindows()