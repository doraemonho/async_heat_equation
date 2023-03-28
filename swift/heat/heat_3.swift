//  Copyright (c) 2022 AUTHORS
//
//  SPDX-License-Identifier: BSL-1.0
//  Distributed under the Boost Software License, Version 1.0. (See accompanying
//  file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
import Foundation

let start = Date()

let C_ARGV = CommandLine.arguments

let nx = Int(C_ARGV[3]) ?? -1  // number of nodes
let k = 0.4  // heat transfer coefficient
let dt = 1.0  // time step
let dx = 1.0  // grid spacing
let nt = Int(C_ARGV[2]) ?? -1  // number of time steps
let threads = Int(C_ARGV[1]) ?? -1  // numnber of threads

struct Worker {

  let space: [UnsafeMutableBufferPointer<Double>]
  var num: Int
  var lo: Int
  var hi: Int

  init(_ p_num: Int, _ tx: Int) {

    num = p_num
    lo = tx * num
    hi = tx * (num + 1)

    space = [
      UnsafeMutableBufferPointer<Double>.allocate(capacity: num + 2),
      UnsafeMutableBufferPointer<Double>.allocate(capacity: num + 2),
    ]

    space[0][0] = 0

    for i in 1...(num) {
      space[0][i] = Double(lo + i)
    }

    space[0][num + 1] = 0

  }

  func update(_ t: Int) {

    let r = (k * dt / (dx * dx))

    let dst =   space[(t + 1) % 2]
    let src = space[t % 2]

    for i in 1...(num - 2) {

    dst[i] =
        (src[i]
          + r
          * (src[i - 1] - 2 * src[i] + src[i + 1]))
    }

  }

  func send_left(_ t: Int) -> Double {

    return space[t % 2][1]

  }

  func send_right(_ t: Int) -> Double {

    return space[t % 2][num - 1]

  }

  func send_ghost(_ left: Worker, _ right: Worker, _ t: Int) {

    left.receiv_right(t, send_left(t))
    right.receiv_left(t, send_right(t))

  }

  func receiv_ghost(_ left: Worker, _ right: Worker, _ t: Int) {

    space[t % 2][0] = left.send_right(t)
    space[t % 2][num - 1] = right.send_left(t)

  }

  func receiv_right(_ t: Int, _ value: Double) {

    space[(t + 1) % 2][num - 1] = value

  }

  func receiv_left(_ t: Int, _ value: Double) {

    space[(t + 1) % 2][0] = value

  }

}

var workerPool: [Worker] = []
let length = Int(nx / threads)

for t in 0...(threads - 1) {

  workerPool.append(Worker(length, t))

}

for t in 0...(nt - 1) {

  await withTaskGroup(
    of: Void.self, returning: Void.self,
    body: { group in

      for p in 0...(threads - 1) {

        group.addTask {

          if threads > 1 {
            if p == 0 {
              await workerPool[p].receiv_ghost(workerPool[threads - 1], workerPool[1], t)
            }

            else if p == threads - 1 {

              await workerPool[p].receiv_ghost(workerPool[p - 1], workerPool[0], t)

            }

            else {

              await workerPool[p].receiv_ghost(workerPool[p - 1], workerPool[p + 1], t)
            }
          }

          await workerPool[p].update(t)

          if threads > 1 {
            if p == 0 {
              await workerPool[p].send_ghost(workerPool[threads - 1], workerPool[1], t)
            }

            else if p == threads - 1 {

              await workerPool[p].send_ghost(workerPool[p - 1], workerPool[0], t)

            }

            else {

              await workerPool[p].send_ghost(workerPool[p - 1], workerPool[p + 1], t)
            }
          }

        }

      }

      for await _ in group {

      }

    })

}

print("swift,\(nx),\(nt),\(threads),\(dt),\(dx),\(-start.timeIntervalSinceNow)")
