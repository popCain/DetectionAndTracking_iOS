# DetectionAndTracking_iOS
Simple Online Realtime Multi-object detection and tracking on mobile device of iOS(*As multiple detected targets enter and exit the frame, unique IDs are created and deleted, and trajectories are created and implemented on iOS for long-term tracking*)  

Test on `iPhone8`(_Test video was token with **`Horizontal screen`**-Orientation_)  
  ![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/objectTracking.gif)
## Tracking Flow(Tracking-by-Detection)
Detector-based data association multi-object tracking
* **Three parts**: **`Detector`**|**`Tracker`**|**`Data Association`**  
![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/trackingFlow.png)

1. **Detector(`Provide detections`)**（*The realtime information of location and appearance to update the objects being tracked*）
    1. Training with Tensorflow Object Detection API using Google Colab
    2. Training with Create ML
    3. Download from [Core ML research community](https://developer.apple.com/machine-learning/models/) 
2. **Tracker(`ii-a(Provide predictions)`)**(*Break the long-term tracking to short-term tracking*)
    1. Single object tracker(*Basic framework of online visual tracking*)
![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/BasicFramework.png)
    3. **`Multi-object tracker`**
        1. **`Detector-independent tracking model`***(Simply a collection of single object trackers)*
            * Reference of [`tracking in Vision of Core ML`](https://developer.apple.com/documentation/vision/tracking_multiple_objects_or_rectangles_in_video)
                > * *Collection of requests: one tracking request per tracked object - 1to1*  
                > * **Limits:**
                >>    * Number of trackers: 16  
                >>    * Long tracking sequence: Objects in tracking sequence can change their shape, appearance, color, location, and that represents a great challenge for the algorithm
                > * **Solution: Breaking the sequence into smaller subsequences, and rerunning detectors every N frames**
            * Reference of OpenCV multi-object tracker
                > * *Collection of single object trackers: BOOSTING, MIL, KCF, TLD, MOSSE, CSRT, MEDIANFLOW, GOTURN*
                > * **Limits:**
                >>    * Swift-OpenCV: You Can't import C++ code directly into Swift. Instead, create an Objective-C or C wrapper for C++ code(Need `bridge file`)
        2. Detector-based tracking model(*Detector-based data association multi-object tracking of `this repository`*)
4. **Data Association**(*Maintain the identity of objects and keep track-`Bridge between detector and short-term traker`*)
    1. Optimized Data Association Algorithm
        1. [Hungarian Maximum Matching Algorithm](https://brilliant.org/wiki/hungarian-matching/)(**`Detections`--Predictions(tracks)`**)
![](https://github.com/popCain/DetectionAndTracking_iOS/blob/main/image/detections_tracks.png)
        2. Nearest Neighbor Filter
    2. Data Association Cost
        1. Appearance Features
        2. Motion Features
