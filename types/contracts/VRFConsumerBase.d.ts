/* Generated by ts-generator ver. 0.0.8 */
/* tslint:disable */

import BN from "bn.js";
import { Contract, ContractOptions } from "web3-eth-contract";
import { EventLog } from "web3-core";
import { EventEmitter } from "events";
import { ContractEvent, Callback, TransactionObject, BlockType } from "./types";

interface EventOptions {
  filter?: object;
  fromBlock?: BlockType;
  topics?: string[];
}

export class VRFConsumerBase extends Contract {
  constructor(
    jsonInterface: any[],
    address?: string,
    options?: ContractOptions
  );
  clone(): VRFConsumerBase;
  methods: {
    fulfillRandomness(
      requestId: string | number[],
      randomness: number | string
    ): TransactionObject<void>;

    nonces(arg0: string | number[]): TransactionObject<string>;

    requestRandomness(
      _keyHash: string | number[],
      _fee: number | string,
      _seed: number | string
    ): TransactionObject<string>;
  };
  events: {
    allEvents: (
      options?: EventOptions,
      cb?: Callback<EventLog>
    ) => EventEmitter;
  };
}