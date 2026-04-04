import Foundation
import QuartzCore

struct ActiveTransition {
    let channelID: Int
    let type: TransitionType
    let startLevel: Float
    let targetLevel: Float
    let duration: TimeInterval
    let startTime: CFTimeInterval
}

@Observable
final class TransitionEngine {
    private var activeTransitions: [Int: ActiveTransition] = [:]

    func triggerTransition(channel: Channel, targetLevel: Float) {
        let config = channel.transitionConfig

        if config.type == .cut {
            channel.faderLevel = targetLevel
            return
        }

        let transition = ActiveTransition(
            channelID: channel.id,
            type: config.type,
            startLevel: channel.faderLevel,
            targetLevel: targetLevel,
            duration: config.duration,
            startTime: CACurrentMediaTime()
        )

        activeTransitions[channel.id] = transition
        channel.isTransitioning = true
    }

    func update(channels: [Channel], timestamp: CFTimeInterval) {
        var completed: [Int] = []

        for (id, transition) in activeTransitions {
            guard id < channels.count else { continue }
            let channel = channels[id]

            let elapsed = timestamp - transition.startTime
            var progress = Float(min(elapsed / transition.duration, 1.0))

            // Ease in-out curve
            progress = progress * progress * (3.0 - 2.0 * progress)

            switch transition.type {
            case .mix:
                let newLevel = transition.startLevel + (transition.targetLevel - transition.startLevel) * progress
                channel.faderLevel = newLevel
                                channel.transitionProgress = progress

            case .dipToBlack:
                let newLevel: Float
                if progress < 0.5 {
                    let phase = progress * 2.0
                    newLevel = transition.startLevel * (1.0 - phase)
                } else {
                    let phase = (progress - 0.5) * 2.0
                    newLevel = transition.targetLevel * phase
                }
                channel.faderLevel = newLevel
                channel.transitionProgress = progress

            case .wipeLeft, .wipeRight, .wipeUp, .wipeDown,
                 .wipeDiagTL, .wipeDiagTR, .wipeCircle, .wipeDiamond, .wipeBlinds, .wipeStar:
                // For wipes: set fader to target immediately so the channel is visible,
                // but the wipe shader uses transitionProgress to spatially reveal/hide
                if channel.faderLevel < transition.targetLevel {
                    channel.faderLevel = transition.targetLevel
                }
                channel.transitionProgress = progress

            case .cut:
                channel.faderLevel = transition.targetLevel
                channel.transitionProgress = 1.0
            }

            if elapsed >= transition.duration {
                channel.faderLevel = transition.targetLevel
                channel.isTransitioning = false
                channel.transitionProgress = 0
                completed.append(id)
            }
        }

        for id in completed {
            activeTransitions.removeValue(forKey: id)
        }
    }

    func cancelTransition(for channel: Channel) {
        activeTransitions.removeValue(forKey: channel.id)
        channel.isTransitioning = false
        channel.transitionProgress = 0
    }

    func isTransitioning(channel: Channel) -> Bool {
        activeTransitions[channel.id] != nil
    }

    func activeTransition(for channel: Channel) -> ActiveTransition? {
        activeTransitions[channel.id]
    }
}
